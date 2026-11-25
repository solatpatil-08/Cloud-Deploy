#!/usr/bin/env bash
# ==============================================================================
# CloudDeploy - Complete AWS Infrastructure Provisioning Script
# Target Region:  ap-south-1 (Mumbai)
#
# Services Provisioned:
# 1. Amazon ECR:        Private Repository 'clouddeploy-task-api' with scan on push
# 2. CloudWatch Logs:   Log groups (/clouddeploy/api, nginx, postgres) with 14d retention
# 3. Security Group:    'CloudDeploy-SG' with Inbound HTTP (80) & HTTPS (443) only
# 4. IAM Role & Profile: 'CloudDeploy-EC2-Role' with SSM Core & least-privilege policy
# 5. SSM Parameters:    SecureString /clouddeploy/prod/DB_PASSWORD, JWT_SECRET, GRAFANA_ADMIN_PASSWORD
# 6. Verification:      Formats and prints validation tables
#
# Idempotent: Safe to execute repeatedly without duplicating or overwriting secrets.
# ==============================================================================

set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
ROLE_NAME="${ROLE_NAME:-CloudDeploy-EC2-Role}"
INSTANCE_PROFILE_NAME="${INSTANCE_PROFILE_NAME:-CloudDeploy-EC2-InstanceProfile}"
POLICY_NAME="${POLICY_NAME:-CloudDeploy-EC2-Policy}"
SG_NAME="${SG_NAME:-CloudDeploy-SG}"
ECR_REPO_NAME="${ECR_REPO_NAME:-clouddeploy-task-api}"
RETENTION_DAYS=14

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${CYAN}================================================================================${NC}"
echo -e "${CYAN}       CloudDeploy AWS Infrastructure Setup - Region: ${AWS_REGION} (Mumbai)       ${NC}"
echo -e "${CYAN}================================================================================${NC}"

# Detect AWS Account ID
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text 2>/dev/null || true)
if [ -z "$AWS_ACCOUNT_ID" ]; then
    echo -e "${RED}Error: Unable to authenticate with AWS CLI. Please configure credentials.${NC}" >&2
    exit 1
fi
echo -e "Authenticated AWS Account: ${CYAN}${AWS_ACCOUNT_ID}${NC} in ${CYAN}${AWS_REGION}${NC}"

# ------------------------------------------------------------------------------
# 1. Amazon ECR Private Repository
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[1/5] Configuring Amazon ECR Repository: '${ECR_REPO_NAME}'...${NC}"

ECR_EXISTS=$(aws ecr describe-repositories \
    --region "$AWS_REGION" \
    --repository-names "$ECR_REPO_NAME" \
    --query "repositories[0].repositoryName" \
    --output text 2>/dev/null || true)

if [ "$ECR_EXISTS" == "$ECR_REPO_NAME" ]; then
    echo -e "  ECR repository ${CYAN}${ECR_REPO_NAME}${NC} already exists."
else
    echo -e "  Creating ECR repository ${CYAN}${ECR_REPO_NAME}${NC} with image scanning..."
    aws ecr create-repository \
        --region "$AWS_REGION" \
        --repository-name "$ECR_REPO_NAME" \
        --image-scanning-configuration scanOnPush=true \
        --image-tag-mutability MUTABLE \
        --encryption-configuration encryptionType=AES256
    echo -e "  ${GREEN}ECR repository created successfully.${NC}"
fi

# ------------------------------------------------------------------------------
# 2. CloudWatch Log Groups with 14-day Retention
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[2/5] Configuring CloudWatch Log Groups (/clouddeploy/*)...${NC}"

LOG_GROUPS=(
    "/clouddeploy/api"
    "/clouddeploy/nginx"
    "/clouddeploy/postgres"
)

for lg in "${LOG_GROUPS[@]}"; do
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

    echo -e "  Setting ${RETENTION_DAYS}-day retention on ${CYAN}${lg}${NC}..."
    aws logs put-retention-policy \
        --region "$AWS_REGION" \
        --log-group-name "$lg" \
        --retention-in-days "$RETENTION_DAYS"
done
echo -e "${GREEN}CloudWatch log groups configured with 14-day retention.${NC}"

# ------------------------------------------------------------------------------
# 3. Security Group (CloudDeploy-SG) - Ports 80 & 443 ONLY
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[3/5] Configuring Security Group '${SG_NAME}'...${NC}"

# Obtain Default VPC ID
DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
    --region "$AWS_REGION" \
    --filters "Name=isDefault,Values=true" \
    --query "Vpcs[0].VpcId" \
    --output text 2>/dev/null || true)

if [ -z "$DEFAULT_VPC_ID" ] || [ "$DEFAULT_VPC_ID" == "None" ]; then
    DEFAULT_VPC_ID=$(aws ec2 describe-vpcs \
        --region "$AWS_REGION" \
        --query "Vpcs[0].VpcId" \
        --output text)
fi
echo -e "  Using VPC: ${CYAN}${DEFAULT_VPC_ID}${NC}"

SG_ID=$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters "Name=group-name,Values=${SG_NAME}" "Name=vpc-id,Values=${DEFAULT_VPC_ID}" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null || true)

if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    echo -e "  Security Group ${CYAN}${SG_NAME}${NC} (${SG_ID}) already exists."
else
    echo -e "  Creating Security Group ${CYAN}${SG_NAME}${NC} in VPC ${DEFAULT_VPC_ID}..."
    SG_ID=$(aws ec2 create-security-group \
        --region "$AWS_REGION" \
        --group-name "$SG_NAME" \
        --description "CloudDeploy EC2 Security Group - HTTP and HTTPS ingress only" \
        --vpc-id "$DEFAULT_VPC_ID" \
        --query "GroupId" \
        --output text)
    echo -e "  ${GREEN}Created Security Group: ${SG_ID}${NC}"
fi

# Configure Inbound Rules (80 and 443 only - Zero Port 22 SSH)
echo -e "  Ensuring Inbound Port 80 (HTTP) rule..."
aws ec2 authorize-security-group-ingress \
    --region "$AWS_REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 2>/dev/null || true

echo -e "  Ensuring Inbound Port 443 (HTTPS) rule..."
aws ec2 authorize-security-group-ingress \
    --region "$AWS_REGION" \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 443 \
    --cidr 0.0.0.0/0 2>/dev/null || true

echo -e "${GREEN}Security Group '${SG_NAME}' configured (Ports 80 & 443 open; Ports 22, 3000, 5432, 8080, 9090 closed).${NC}"

# ------------------------------------------------------------------------------
# 4. IAM Role and Instance Profile (CloudDeploy-EC2-Role)
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[4/5] Configuring IAM Role and Instance Profile...${NC}"

# 4a. Trust Policy
TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
)

ROLE_EXISTS=$(aws iam get-role \
    --role-name "$ROLE_NAME" \
    --query "Role.RoleName" \
    --output text 2>/dev/null || true)

if [ "$ROLE_EXISTS" == "$ROLE_NAME" ]; then
    echo -e "  IAM Role ${CYAN}${ROLE_NAME}${NC} already exists."
else
    echo -e "  Creating IAM Role ${CYAN}${ROLE_NAME}${NC}..."
    aws iam create-role \
        --role-name "$ROLE_NAME" \
        --assume-role-policy-document "$TRUST_POLICY" \
        --description "Role for CloudDeploy EC2 instance with SSM, ECR, and CloudWatch least-privilege"
fi

# 4b. Attach AmazonSSMManagedInstanceCore
echo -e "  Attaching managed policy 'AmazonSSMManagedInstanceCore'..."
aws iam attach-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

# 4c. Attach Least-Privilege Inline Policy
echo -e "  Applying least-privilege inline policy '${POLICY_NAME}'..."
LEAST_PRIVILEGE_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAuthToken",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECRPullImageLayers",
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "arn:aws:ecr:${AWS_REGION}:${AWS_ACCOUNT_ID}:repository/${ECR_REPO_NAME}"
    },
    {
      "Sid": "CloudWatchLogsWrite",
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
      "Sid": "SSMParameterStoreRead",
      "Effect": "Allow",
      "Action": [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ],
      "Resource": "arn:aws:ssm:${AWS_REGION}:${AWS_ACCOUNT_ID}:parameter/clouddeploy/prod/*"
    },
    {
      "Sid": "KMSDecryptSSMSecrets",
      "Effect": "Allow",
      "Action": [
        "kms:Decrypt"
      ],
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

aws iam put-role-policy \
    --role-name "$ROLE_NAME" \
    --policy-name "$POLICY_NAME" \
    --policy-document "$LEAST_PRIVILEGE_POLICY"

# 4d. Instance Profile
PROFILE_EXISTS=$(aws iam get-instance-profile \
    --instance-profile-name "$INSTANCE_PROFILE_NAME" \
    --query "InstanceProfile.InstanceProfileName" \
    --output text 2>/dev/null || true)

if [ "$PROFILE_EXISTS" == "$INSTANCE_PROFILE_NAME" ]; then
    echo -e "  Instance Profile ${CYAN}${INSTANCE_PROFILE_NAME}${NC} already exists."
else
    echo -e "  Creating Instance Profile ${CYAN}${INSTANCE_PROFILE_NAME}${NC}..."
    aws iam create-instance-profile \
        --instance-profile-name "$INSTANCE_PROFILE_NAME"
    echo -e "  Adding role to instance profile..."
    aws iam add-role-to-instance-profile \
        --instance-profile-name "$INSTANCE_PROFILE_NAME" \
        --role-name "$ROLE_NAME"
fi
echo -e "${GREEN}IAM Role and Instance Profile ready.${NC}"

# ------------------------------------------------------------------------------
# 5. SSM Parameter Store SecureString Parameters
# ------------------------------------------------------------------------------
echo -e "\n${YELLOW}[5/5] Configuring SSM SecureString Parameters...${NC}"

SSM_PARAMS=(
    "/clouddeploy/prod/DB_PASSWORD"
    "/clouddeploy/prod/JWT_SECRET"
    "/clouddeploy/prod/GRAFANA_ADMIN_PASSWORD"
)

for param in "${SSM_PARAMS[@]}"; do
    PARAM_EXISTS=$(aws ssm get-parameter \
        --region "$AWS_REGION" \
        --name "$param" \
        --query "Parameter.Name" \
        --output text 2>/dev/null || true)

    if [ "$PARAM_EXISTS" == "$param" ]; then
        echo -e "  Parameter ${CYAN}${param}${NC} already exists. Preserving secret."
    else
        echo -e "  Generating SecureString for ${CYAN}${param}${NC}..."
        GENERATED_SECRET=$(openssl rand -base64 32)
        aws ssm put-parameter \
            --region "$AWS_REGION" \
            --name "$param" \
            --type "SecureString" \
            --value "$GENERATED_SECRET" \
            --description "CloudDeploy Production secret for $(basename "$param")" \
            --tier "Standard"
        unset GENERATED_SECRET
        echo -e "  ${GREEN}Created SecureString parameter: ${param}${NC}"
    fi
done

# ------------------------------------------------------------------------------
# Verification Output
# ------------------------------------------------------------------------------
echo -e "\n${CYAN}================================================================================${NC}"
echo -e "${CYAN}                         AWS INFRASTRUCTURE VERIFICATION                        ${NC}"
echo -e "${CYAN}================================================================================${NC}"

echo -e "\n${YELLOW}1. Amazon ECR Repository:${NC}"
aws ecr describe-repositories \
    --region "$AWS_REGION" \
    --repository-names "$ECR_REPO_NAME" \
    --query "repositories[*].[repositoryName, repositoryUri, imageTagMutability]" \
    --output table

echo -e "\n${YELLOW}2. CloudWatch Log Groups (14-Day Retention):${NC}"
aws logs describe-log-groups \
    --region "$AWS_REGION" \
    --log-group-name-prefix "/clouddeploy/" \
    --query "logGroups[?starts_with(logGroupName, '/clouddeploy/')].[logGroupName, retentionInDays]" \
    --output table

echo -e "\n${YELLOW}3. Security Group Ingress Rules (CloudDeploy-SG):${NC}"
aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --group-ids "$SG_ID" \
    --query "SecurityGroups[*].IpPermissions[*].[IpProtocol, FromPort, ToPort, IpRanges[0].CidrIp]" \
    --output table

echo -e "\n${YELLOW}4. IAM Role Attached Policies & Instance Profile:${NC}"
echo -e "Instance Profile: ${CYAN}${INSTANCE_PROFILE_NAME}${NC}"
aws iam list-attached-role-policies \
    --role-name "$ROLE_NAME" \
    --output table
aws iam list-role-policies \
    --role-name "$ROLE_NAME" \
    --output table

echo -e "\n${YELLOW}5. SSM Parameter Store Metadata (Values Hidden):${NC}"
aws ssm describe-parameters \
    --region "$AWS_REGION" \
    --parameter-filters "Key=Name,Option=BeginsWith,Values=/clouddeploy/prod/" \
    --query "Parameters[*].[Name, Type, Version, LastModifiedDate]" \
    --output table

echo -e "\n${GREEN}================================================================================${NC}"
echo -e "${GREEN}   AWS Infrastructure setup and validation complete for ap-south-1 (Mumbai)!    ${NC}"
echo -e "${GREEN}================================================================================${NC}"
