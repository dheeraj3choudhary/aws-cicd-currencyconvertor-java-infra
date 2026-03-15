<div align="center">

# Currency Convertor Infra Pipeline
Infrastructure repository for the Currency Converter portfolio project.Contains all CloudFormation stacks, the bootstrap template, and the teardown script.
The companion application repository is [currency-application](https://github.com/dheeraj3choudhary/aws-cicd-currencyconvertor-java-application).



[![AWS CloudFormation](https://img.shields.io/badge/CloudFormation-FF4F8B?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/cloudformation/)
[![AWS CodePipeline](https://img.shields.io/badge/CodePipeline-232F3E?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/codepipeline/)
[![AWS CodeBuild](https://img.shields.io/badge/CodeBuild-232F3E?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/codebuild/)
[![AWS CodeCommit](https://img.shields.io/badge/CodeCommit-232F3E?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/codecommit/)
[![AWS Elastic Beanstalk](https://img.shields.io/badge/Elastic%20Beanstalk-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/elasticbeanstalk/)
[![AWS ECR](https://img.shields.io/badge/ECR-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/ecr/)
[![AWS IAM](https://img.shields.io/badge/IAM-DD344C?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/iam/)
[![AWS S3](https://img.shields.io/badge/S3-569A31?style=for-the-badge&logo=amazons3&logoColor=white)](https://aws.amazon.com/s3/)
[![AWS SSM](https://img.shields.io/badge/SSM-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)](https://aws.amazon.com/systems-manager/)

<a href="https://www.buymeacoffee.com/Dheeraj3" target="_blank">
  <img src="https://cdn.buymeacoffee.com/buttons/v2/default-blue.png" alt="Buy Me A Coffee" height="50">
</a>

## [Subscribe](https://www.youtube.com/@dheeraj-choudhary?sub_confirmation=1) to learn more About Artificial-Intellegence, Machine-Learning, Cloud & DevOps.

<p align="center">
<a href="https://www.linkedin.com/in/dheeraj-choudhary/" target="_blank">
  <img height="100" alt="Dheeraj Choudhary | LinkedIN"  src="https://user-images.githubusercontent.com/60597290/152035581-a7c6c0c3-65c3-4160-89c0-e90ddc1e8d4e.png"/>
</a> 

<a href="https://www.youtube.com/@dheeraj-choudhary?sub_confirmation=1">
    <img height="100" src="https://user-images.githubusercontent.com/60597290/152035929-b7f75d38-e1c2-4325-a97e-7b934b8534e2.png" />
</a>    
</p>

</div>


---

## Architecture Overview

```
                        ┌─────────────────────────────────────────┐
                        │           bootstrap.yml (one-time)       │
                        │  Creates repos, pipelines, IAM, S3       │
                        └───────────────┬─────────────────────────┘
                                        │
              ┌─────────────────────────┴──────────────────────────┐
              │                                                      │
              ▼                                                      ▼
  ┌───────────────────────┐                          ┌───────────────────────┐
  │  currency-converter   │                          │   currency-application │
  │       -infra          │                          │        repo            │
  │  (this repo)          │                          │  (app repo)            │
  └──────────┬────────────┘                          └──────────┬────────────┘
             │ push                                             │ push
             ▼                                                  ▼
  ┌───────────────────────┐                          ┌───────────────────────┐
  │   infra pipeline      │                          │    app pipeline        │
  │  buildspec-infra.yml  │                          │  buildspec-build.yml   │
  └──────────┬────────────┘                          │  buildspec-docker.yml  │
             │                                       └──────────┬────────────┘
             ▼                                                  │
  ┌───────────────────────┐                                     ▼
  │  CFN Stacks (in order)│                          ┌───────────────────────┐
  │  1. iam.yml           │                          │  Elastic Beanstalk    │
  │  2. ecr.yml           │◄─────────────────────────│  Docker environment   │
  │  3. s3.yml            │   app deploys here       │                       │
  │  4. beanstalk.yml     │                          └───────────────────────┘
  └───────────────────────┘
```

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
