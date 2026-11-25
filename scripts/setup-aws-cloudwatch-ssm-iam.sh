#!/usr/bin/env bash
# ==============================================================================
# CloudDeploy AWS Infrastructure Setup Script
# Region:     ap-southeast-2 (Sydney)
# Account:    245908834556
#
# Tasks:
# 1. Create CloudWatch Log Groups with 14-day retention (/clouddeploy/api, nginx, postgres)
# 2. Attach least-privilege inline policy CloudDeploy-Restricted to CloudDeploy-EC2-Role
# 3. Create SecureString SSM parameters (/clouddeploy/prod/DB_PASSWORD, JWT_SECRET, GRAFANA_ADMIN_PASSWORD)
# 4. Print verification outputs
#
# Idempotent: Safe to execute multiple times without overwriting existing secrets.
# ==============================================================================

set -euo pipefail

# Configuration
AWS_REGION="${AWS_REGION:-ap-south-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || echo "245908834556")}"
ROLE_NAME="${ROLE_NAME:-CloudDeploy-EC2-Role}"
POLICY_NAME="${POLICY_NAME:-CloudDeploy-Restricted}"
RETENTION_DAYS=14

# Colors for terminal output
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}================================================================${NC}"
echo -e "${CYAN}     CloudDeploy AWS Setup: CloudWatch, IAM & SSM Parameters    ${NC}"
echo -e "${CYAN}     Region: ${AWS_REGION} | Account: ${AWS_ACCOUNT_ID}          ${NC}"
echo -e "${CYAN}================================================================${NC}"

# ------------------------------------------------------------------------------
# 1. CloudWatch Log Groups with 14-day Retention
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[1/4] Configuring CloudWatch Log Groups...${NC}"

LOG_GROUPS=(
    "/clouddeploy/api"
    "/clouddeploy/nginx"
    "/clouddeploy/postgres"
)

for lg in "${LOG_GROUPS[@]}"; do
    # Check if log group exists
    EXISTING_LG=$(aws logs describe-log-groups \
        --region "$AWS_REGION" \
        --log-group-name-prefix "$lg" \
        --query "logGroups[?logGroupName=='$lg'].logGroupName" \
        --output text 2>/dev/null || true)

    if [ "$EXISTING_LG" == "$lg" ]; then
        echo -e "  Log group ${CYAN}${lg}${NC} already exists."
    else
        echo -e "  Creating log group ${CYAN}${lg}${NC}..."
        aws logs create-log-group \
            --region "$AWS_REGION" \
            --log-group-name "$lg"
    fi

    # Set 14-day retention policy (idempotent)
    echo -e "  Applying ${RETENTION_DAYS}-day retention policy to ${CYAN}${lg}${NC}..."
    aws logs put-retention-policy \
        --region "$AWS_REGION" \
        --log-group-name "$lg" \
        --retention-in-days "$RETENTION_DAYS"
done

echo -e "${GREEN}CloudWatch log groups configured successfully.${NC}"

# ------------------------------------------------------------------------------
# 2. Update Inline Policy on CloudDeploy-EC2-Role (Least Privilege)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[2/4] Updating IAM inline policy '${POLICY_NAME}' on '${ROLE_NAME}'...${NC}"

# Least-privilege IAM policy document
POLICY_DOCUMENT=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "CloudWatchLogsDelivery",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams"
      ],
      "Resource": [
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/clouddeploy/*",
        "arn:aws:logs:${AWS_REGION}:${AWS_ACCOUNT_ID}:log-group:/clouddeploy/*:*"
      ]
    },
    {
      "Sid": "SSMParameterStoreReadAccess",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/clouddeploy/prod/*"
    },
    {
      "Sid": "KMSDecryptForSSMSecrets",
      "Effect": "Allow",
      "Action": "kms:Decrypt",
      "Resource": "*",
      "Condition": {
        "StringEquals": {
          "kms:ViaService": "ssm.${AWS_REGION}.amazonaws.com"
        }
      }
    }
  ]
}
EOF
)

# Apply policy (idempotent: creates if missing, updates if exists)
aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --policy-document "$POLICY_DOCUMENT"

echo -e "${GREEN}Inline policy '${POLICY_NAME}' successfully applied to '${ROLE_NAME}'.${NC}"

# ------------------------------------------------------------------------------
# 3. Create SecureString SSM Parameters (Idempotent - Preserves Existing Values)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[3/4] Configuring SSM SecureString parameters under /clouddeploy/prod/...${NC}"

SSM_PARAMETERS=(
    "/clouddeploy/prod/DB_PASSWORD"
    "/clouddeploy/prod/JWT_SECRET"
    "/clouddeploy/prod/GRAFANA_ADMIN_PASSWORD"
)

for param in "${SSM_PARAMETERS[@]}"; do
    # Check if parameter already exists to preserve existing values
    PARAM_EXISTS=$(aws ssm get-parameter \
        --region "$AWS_REGION" \
        --name "$param" \
        --query "Parameter.Name" \
        --output text 2>/dev/null || true)

    if [ "$PARAM_EXISTS" == "$param" ]; then
        echo -e "  Parameter ${CYAN}${param}${NC} already exists. Preserving current secret."
    else
        echo -e "  Generating new random secret for ${CYAN}${param}${NC}..."
        # In-memory generation using openssl (no hardcoding or disk writes)
        GENERATED_SECRET=$(openssl rand -base64 32)

        aws ssm put-parameter \
            --region "$AWS_REGION" \
            --name "$param" \
            --type "SecureString" \
            --value "$GENERATED_SECRET" \
            --description "CloudDeploy production secret for $(basename "$param")" \
            --tier "Standard"

        # Wipe secret from memory
        unset GENERATED_SECRET
        echo -e "  ${GREEN}Created SecureString parameter: ${param}${NC}"
    fi
done

# ------------------------------------------------------------------------------
# 4. Verification Output
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}================================================================${NC}"
echo -e "${CYAN}                       VERIFICATION OUTPUT                      ${NC}"
echo -e "${CYAN}================================================================${NC}"

echo -e "\n${YELLOW}1. CloudWatch Log Groups & Retention:${NC}"
aws logs describe-log-groups \
    --region "$AWS_REGION" \
    --log-group-name-prefix "/clouddeploy/" \
    --query "logGroups[?starts_with(logGroupName, '/clouddeploy/')].[logGroupName, retentionInDays, storedBytes]" \
    --output table

echo -e "\n${YELLOW}2. Active IAM Inline Policy (${POLICY_NAME}):${NC}"
aws iam get-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --query "PolicyDocument" \
    --output json

echo -e "\n${YELLOW}3. SSM Parameter Store Metadata (Values Hidden):${NC}"
aws ssm describe-parameters \
    --region "$AWS_REGION" \
    --parameter-filters "Key=Name,Option=BeginsWith,Values=/clouddeploy/prod/" \
    --query "Parameters[*].[Name, Type, Version, LastModifiedDate]" \
    --output table

echo -e "\n${GREEN}Setup and verification complete.${NC}"
