#!/bin/bash
# ---------------------------------------------------------------------------
# teardown.sh
# Deletes all Currency Converter AWS resources in safe reverse dependency order.
#
# Usage:
#   chmod +x scripts/teardown.sh
#   ./scripts/teardown.sh
#
# What this script does:
#   1.  Empties and deletes the EB versions S3 bucket
#   2.  Empties and deletes the pipeline artifacts S3 bucket
#   3.  Deletes all ECR images then the ECR repository
#   4.  Deletes CFN stacks: beanstalk → s3 → ecr → iam (reverse order)
#   5.  Deletes CodePipelines
#   6.  Deletes CodeBuild projects
#   7.  Deletes EventBridge rules
#   8.  Deletes CodeCommit repositories
#   9.  Deletes the bootstrap CloudFormation stack
#
# Pre-requisite: AWS CLI configured with sufficient permissions.
# Region is hardcoded to us-west-2 to match the project.
# ---------------------------------------------------------------------------

set -e

REGION="us-west-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "========================================"
echo " Currency Converter — Teardown Script"
echo " Account : $ACCOUNT_ID"
echo " Region  : $REGION"
echo "========================================"
echo ""
echo "WARNING: This will permanently delete all project resources."
read -p "Type 'yes' to continue: " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
  echo "Teardown cancelled."
  exit 0
fi

# ---------------------------------------------------------------------------
# Helper — empty and delete an S3 bucket (handles versioned buckets)
# ---------------------------------------------------------------------------
empty_and_delete_bucket() {
  local BUCKET=$1
  echo "  Checking bucket: $BUCKET"

  if ! aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
    echo "  Bucket $BUCKET does not exist, skipping."
    return
  fi

  echo "  Deleting all object versions in $BUCKET..."
  aws s3api list-object-versions \
    --bucket "$BUCKET" \
    --output json \
    --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' \
  | jq -c '.Objects // [] | select(length > 0)' \
  | while read -r OBJECTS; do
      aws s3api delete-objects \
        --bucket "$BUCKET" \
        --delete "$OBJECTS" \
        --region "$REGION" > /dev/null
    done

  echo "  Deleting all delete markers in $BUCKET..."
  aws s3api list-object-versions \
    --bucket "$BUCKET" \
    --output json \
    --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' \
  | jq -c '.Objects // [] | select(length > 0)' \
  | while read -r OBJECTS; do
      aws s3api delete-objects \
        --bucket "$BUCKET" \
        --delete "$OBJECTS" \
        --region "$REGION" > /dev/null
    done

  echo "  Deleting bucket $BUCKET..."
  aws s3api delete-bucket --bucket "$BUCKET" --region "$REGION"
  echo "  Bucket $BUCKET deleted."
}

# ---------------------------------------------------------------------------
# Helper — delete a CFN stack and wait for completion
# ---------------------------------------------------------------------------
delete_stack() {
  local STACK=$1
  echo "  Deleting stack: $STACK"

  STATUS=$(aws cloudformation describe-stacks \
    --stack-name "$STACK" \
    --region "$REGION" \
    --query "Stacks[0].StackStatus" \
    --output text 2>/dev/null || echo "DOES_NOT_EXIST")

  if [ "$STATUS" = "DOES_NOT_EXIST" ]; then
    echo "  Stack $STACK does not exist, skipping."
    return
  fi

  aws cloudformation delete-stack \
    --stack-name "$STACK" \
    --region "$REGION"

  echo "  Waiting for $STACK to be deleted..."
  aws cloudformation wait stack-delete-complete \
    --stack-name "$STACK" \
    --region "$REGION"

  echo "  Stack $STACK deleted."
}

# ---------------------------------------------------------------------------
# Step 1 — Empty and delete S3 buckets
# ---------------------------------------------------------------------------
echo ""
echo "[1/9] Deleting S3 buckets..."
empty_and_delete_bucket "currency-converter-eb-versions-${ACCOUNT_ID}"
empty_and_delete_bucket "currency-converter-artifacts-${ACCOUNT_ID}"

# ---------------------------------------------------------------------------
# Step 2 — Delete all ECR images then the repository
# ---------------------------------------------------------------------------
echo ""
echo "[2/9] Deleting ECR images and repository..."
ECR_REPO="currency-converter"

if aws ecr describe-repositories --repository-names "$ECR_REPO" --region "$REGION" 2>/dev/null; then
  IMAGE_IDS=$(aws ecr list-images \
    --repository-name "$ECR_REPO" \
    --region "$REGION" \
    --query 'imageIds[*]' \
    --output json)

  if [ "$IMAGE_IDS" != "[]" ]; then
    echo "  Deleting ECR images..."
    aws ecr batch-delete-image \
      --repository-name "$ECR_REPO" \
      --image-ids "$IMAGE_IDS" \
      --region "$REGION" > /dev/null
  fi

  echo "  Deleting ECR repository..."
  aws ecr delete-repository \
    --repository-name "$ECR_REPO" \
    --force \
    --region "$REGION" > /dev/null
  echo "  ECR repository deleted."
else
  echo "  ECR repository does not exist, skipping."
fi

# ---------------------------------------------------------------------------
# Step 3 — Delete CFN stacks in reverse dependency order
# ---------------------------------------------------------------------------
echo ""
echo "[3/9] Deleting CloudFormation stacks (reverse order)..."
delete_stack "currency-converter-beanstalk"
delete_stack "currency-converter-s3"
delete_stack "currency-converter-ecr"
delete_stack "currency-converter-iam"

# ---------------------------------------------------------------------------
# Step 4 — Delete CodePipelines
# ---------------------------------------------------------------------------
echo ""
echo "[4/9] Deleting CodePipelines..."
for PIPELINE in currency-converter-infra-pipeline currency-converter-app-pipeline; do
  if aws codepipeline get-pipeline --name "$PIPELINE" --region "$REGION" 2>/dev/null; then
    aws codepipeline delete-pipeline --name "$PIPELINE" --region "$REGION"
    echo "  Pipeline $PIPELINE deleted."
  else
    echo "  Pipeline $PIPELINE does not exist, skipping."
  fi
done

# ---------------------------------------------------------------------------
# Step 5 — Delete CodeBuild projects
# ---------------------------------------------------------------------------
echo ""
echo "[5/9] Deleting CodeBuild projects..."
for PROJECT in \
  currency-converter-infra-build \
  currency-converter-app-build \
  currency-converter-app-docker; do
  if aws codebuild batch-get-projects --names "$PROJECT" --region "$REGION" \
      --query "projects[0].name" --output text 2>/dev/null | grep -q "$PROJECT"; then
    aws codebuild delete-project --name "$PROJECT" --region "$REGION"
    echo "  CodeBuild project $PROJECT deleted."
  else
    echo "  CodeBuild project $PROJECT does not exist, skipping."
  fi
done

# ---------------------------------------------------------------------------
# Step 6 — Delete EventBridge rules
# ---------------------------------------------------------------------------
echo ""
echo "[6/9] Deleting EventBridge rules..."
for RULE in currency-converter-infra-trigger currency-converter-app-trigger; do
  if aws events describe-rule --name "$RULE" --region "$REGION" 2>/dev/null; then
    # Remove targets before deleting the rule
    TARGET_IDS=$(aws events list-targets-by-rule \
      --rule "$RULE" \
      --region "$REGION" \
      --query "Targets[*].Id" \
      --output text)
    if [ -n "$TARGET_IDS" ]; then
      aws events remove-targets \
        --rule "$RULE" \
        --ids $TARGET_IDS \
        --region "$REGION" > /dev/null
    fi
    aws events delete-rule --name "$RULE" --region "$REGION"
    echo "  EventBridge rule $RULE deleted."
  else
    echo "  EventBridge rule $RULE does not exist, skipping."
  fi
done

# ---------------------------------------------------------------------------
# Step 7 — Delete CodeCommit repositories
# ---------------------------------------------------------------------------
echo ""
echo "[7/9] Deleting CodeCommit repositories..."
for REPO in currency-converter-infra currency-application; do
  if aws codecommit get-repository --repository-name "$REPO" --region "$REGION" 2>/dev/null; then
    aws codecommit delete-repository --repository-name "$REPO" --region "$REGION"
    echo "  CodeCommit repo $REPO deleted."
  else
    echo "  CodeCommit repo $REPO does not exist, skipping."
  fi
done

# ---------------------------------------------------------------------------
# Step 8 — Delete bootstrap CloudFormation stack
# ---------------------------------------------------------------------------
echo ""
echo "[8/9] Deleting bootstrap CloudFormation stack..."
delete_stack "currency-converter-bootstrap"

# ---------------------------------------------------------------------------
# Step 9 — Remind about manually created resources
# ---------------------------------------------------------------------------
echo ""
echo "[9/9] Manual cleanup reminder..."
echo "  The following resource was created manually and must be deleted manually:"
echo ""
echo "  SSM Parameter:"
echo "    aws ssm delete-parameter \\"
echo "      --name \"/currency-converter/api-key\" \\"
echo "      --region $REGION"
echo ""

echo "========================================"
echo " Teardown complete."
echo "========================================"