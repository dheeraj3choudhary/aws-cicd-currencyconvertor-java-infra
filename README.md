# currency-converter-infra

Infrastructure repository for the Currency Converter portfolio project.
Contains all CloudFormation stacks, the bootstrap template, and the teardown script.

The companion application repository is [currency-application](https://git-codecommit.us-west-2.amazonaws.com/v1/repos/currency-application).

---

## Architecture Overview



## Repository Structure

```
currency-converter-infra/
├── bootstrap/
│   └── bootstrap.yml           # Deployed once from console
├── stacks/
│   ├── iam.yml                 # EC2 instance profile + Beanstalk service role
│   ├── ecr.yml                 # ECR Docker image repository
│   ├── s3.yml                  # S3 bucket for EB application versions
│   └── beanstalk.yml           # Beanstalk application + environment
├── pipeline/
│   └── buildspec-infra.yml     # Deploys CFN stacks in order
├── scripts/
│   └── teardown.sh             # Cleans up all resources in reverse order
├── .gitignore
└── README.md
```

---

## Prerequisites

The following must be in place before deploying the bootstrap stack.

### 1. AWS CLI configured

```bash
aws configure
# Default region: us-west-2
```

### 2. Create the API key SSM Parameter

The Beanstalk environment reads the exchangerate-api.com key from SSM at creation time.
This is the only resource created outside of CloudFormation.

```bash
aws ssm put-parameter \
  --name "/currency-converter/api-key" \
  --value "<your-exchangerate-api-key>" \
  --type SecureString \
  --region us-west-2
```

Get a free API key at [exchangerate-api.com](https://www.exchangerate-api.com).

---

## Deployment

### Step 1 — Deploy the bootstrap stack from the AWS Console

1. Open **CloudFormation** in the AWS Console (`us-west-2`)
2. Click **Create stack → With new resources**
3. Upload `bootstrap/bootstrap.yml`
4. Stack name: `currency-converter-bootstrap`
5. Leave parameters as default and deploy

This creates:
- Both CodeCommit repositories
- Shared S3 artifact bucket
- All IAM roles for CodePipeline and CodeBuild
- All three CodeBuild projects
- Both CodePipelines with EventBridge triggers

### Step 2 — Push this repo to CodeCommit

```bash
# Clone the empty repo created by bootstrap
git clone https://git-codecommit.us-west-2.amazonaws.com/v1/repos/currency-converter-infra
cd currency-converter-infra

# Copy all files from this repo into the cloned directory, then:
git add .
git commit -m "Initial infrastructure commit"
git push origin master
```

The infra pipeline triggers automatically and deploys all four CFN stacks in order:
`iam` → `ecr` → `s3` → `beanstalk`

### Step 3 — Push the application repo

See the [currency-application README](https://git-codecommit.us-west-2.amazonaws.com/v1/repos/currency-application) for the next step.

---

## CloudFormation Stacks

| Stack name                    | Template            | Deploys                                         |
|-------------------------------|---------------------|-------------------------------------------------|
| `currency-converter-bootstrap`| bootstrap.yml       | Repos, pipelines, CodeBuild, IAM, S3 (artifact) |
| `currency-converter-iam`      | stacks/iam.yml      | EC2 instance profile, Beanstalk service role     |
| `currency-converter-ecr`      | stacks/ecr.yml      | ECR repository                                  |
| `currency-converter-s3`       | stacks/s3.yml       | S3 bucket for EB application versions           |
| `currency-converter-beanstalk`| stacks/beanstalk.yml| Beanstalk application and environment           |

---

## Stack Outputs and Cross-Stack References

`beanstalk.yml` consumes outputs from `iam.yml` via `ImportValue`:

| Export name                                  | Source     | Consumed by   |
|----------------------------------------------|------------|---------------|
| `currency-converter-ec2-instance-profile`    | iam.yml    | beanstalk.yml |
| `currency-converter-beanstalk-service-role-arn` | iam.yml | beanstalk.yml |
| `currency-converter-ecr-uri`                 | ecr.yml    | buildspec-docker.yml (app repo) |
| `currency-converter-eb-versions-bucket`      | s3.yml     | buildspec-docker.yml (app repo) |
| `currency-converter-eb-application-name`     | beanstalk.yml | app pipeline deploy stage |
| `currency-converter-eb-environment-name`     | beanstalk.yml | app pipeline deploy stage |

---

## Teardown

To delete all project resources:

```bash
chmod +x scripts/teardown.sh
./scripts/teardown.sh
```

The script deletes everything in safe reverse dependency order and reminds you
to manually delete the SSM parameter at the end.

**Teardown order:**
1. Empty and delete S3 buckets
2. Delete ECR images and repository
3. Delete CFN stacks: `beanstalk` → `s3` → `ecr` → `iam`
4. Delete CodePipelines
5. Delete CodeBuild projects
6. Delete EventBridge rules
7. Delete CodeCommit repositories
8. Delete bootstrap CFN stack
9. *(Manual)* Delete SSM parameter

---

## Rules

- Nothing is created via the AWS Console except the bootstrap stack and the SSM parameter
- All infrastructure is defined in CloudFormation
- No dev/staging/prod environments — single environment only
- No SNS notifications
- The app runs inside a Docker container on Elastic Beanstalk
- The API key is stored as an SSM SecureString and never appears in code or logs