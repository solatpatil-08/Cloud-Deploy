# AWS Systems Manager (SSM) Host Bootstrapping & Administration Guide

This guide details how to remotely bootstrap, deploy, monitor, and troubleshoot the **CloudDeploy** application server on **Amazon EC2 (Amazon Linux 2023)** without opening inbound SSH port 22.

---

## 1. Prerequisites

1. **EC2 Instance Profile**: Ensure `CloudDeploy-EC2-Role` is attached to your EC2 instance (`CloudDeploy-Server`).
2. **SSM Agent**: Active on the instance (pre-installed and active by default on Amazon Linux 2023).
3. **Outbound Internet**: Instance resides in a subnet with internet access (IGW or NAT Gateway) to communicate with the AWS Systems Manager endpoints.
4. **AWS CLI / AWS Console Access**: Valid credentials with permissions to invoke `ssm:SendCommand` and `ssm:StartSession`.

---

## 2. Bootstrapping the Server via AWS Systems Manager

### Method A: Using AWS CLI (Run Command)

To run [`scripts/bootstrap-ec2.sh`](file:///c:/CloudDeploy/scripts/bootstrap-ec2.sh) on the remote EC2 instance via AWS SSM:

```bash
# 1. Identify Instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
    --region ap-south-1 \
    --filters "Name=tag:Name,Values=CloudDeploy-Server" "Name=instance-state-name,Values=running" \
    --query "Reservations[0].Instances[0].InstanceId" \
    --output text)

echo "Targeting Instance: ${INSTANCE_ID}"

# 2. Execute Bootstrap Commands via AWS Systems Manager Run Command
COMMAND_ID=$(aws ssm send-command \
    --region ap-south-1 \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "Bootstrap CloudDeploy Docker and Environment" \
    --parameters 'commands=[
        "mkdir -p /opt/clouddeploy/scripts /opt/clouddeploy/logs",
        "cd /opt/clouddeploy",
        "curl -sSL https://raw.githubusercontent.com/solatpatil-08/Cloud-Deploy/main/scripts/bootstrap-ec2.sh -o /opt/clouddeploy/scripts/bootstrap-ec2.sh",
        "chmod +x /opt/clouddeploy/scripts/bootstrap-ec2.sh",
        "bash /opt/clouddeploy/scripts/bootstrap-ec2.sh"
    ]' \
    --query "Command.CommandId" \
    --output text)

echo "Sent Command ID: ${COMMAND_ID}"

# 3. Track Command Execution Status & Logs
aws ssm get-command-invocation \
    --region ap-south-1 \
    --command-id "$COMMAND_ID" \
    --instance-id "$INSTANCE_ID" \
    --query "[Status, StandardOutputContent]" \
    --output text
```

---

### Method B: Using AWS Management Console

1. Open the [AWS Systems Manager Console](https://ap-south-1.console.aws.amazon.com/systems-manager/home?region=ap-south-1).
2. In the left navigation pane, select **Node Management** → **Run Command**.
3. Click the **Run command** button.
4. **Command document**:
   - In the search box, search for: `AWS-RunShellScript` and select it.
5. **Command parameters**:
   In the **Commands** box, paste:
   ```bash
   #!/bin/bash
   set -euo pipefail
   mkdir -p /opt/clouddeploy/scripts /opt/clouddeploy/logs
   cd /opt/clouddeploy
   curl -sSL https://raw.githubusercontent.com/solatpatil-08/Cloud-Deploy/main/scripts/bootstrap-ec2.sh -o /opt/clouddeploy/scripts/bootstrap-ec2.sh
   chmod +x /opt/clouddeploy/scripts/bootstrap-ec2.sh
   bash /opt/clouddeploy/scripts/bootstrap-ec2.sh
   ```
6. **Targets**:
   - Choose **Choose instances manually**.
   - Select your running instance: **`CloudDeploy-Server`**.
7. **Output options**:
   - (Optional) Enable CloudWatch output to `/clouddeploy/nginx` or `/clouddeploy/api` or leave S3 unticked.
8. Click **Run**.
9. View real-time stdout and stderr logs under the command execution screen.

---

## 3. Remote Shell Access (Session Manager)

To open an interactive shell without an SSH key pair or open port 22:

### Via AWS CLI:
```bash
aws ssm start-session \
    --region ap-south-1 \
    --target "$INSTANCE_ID"
```

Inside the Session Manager shell, switch to the application workspace:
```bash
sudo su - ec2-user
cd /opt/clouddeploy
./scripts/health-check.sh
```

### Via AWS Console:
1. Open **EC2 → Instances → CloudDeploy-Server**.
2. Click **Connect** in the top action bar.
3. Select the **Session Manager** tab.
4. Click **Connect**.

---

## 4. Deploying & Rolling Back via SSM Run Command

### Triggering a New Deployment:
```bash
aws ssm send-command \
    --region ap-south-1 \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "Deploy image v1.0.0" \
    --parameters 'commands=[
        "cd /opt/clouddeploy",
        "bash scripts/deploy.sh v1.0.0"
    ]'
```

### Triggering an Automated Rollback:
```bash
aws ssm send-command \
    --region ap-south-1 \
    --instance-ids "$INSTANCE_ID" \
    --document-name "AWS-RunShellScript" \
    --comment "Emergency Rollback to previous version" \
    --parameters 'commands=[
        "cd /opt/clouddeploy",
        "bash scripts/rollback.sh"
    ]'
```

---

## 5. Administrative Port Forwarding (Prometheus & Grafana)

Because Prometheus (`:9090`) and Grafana (`:3000`) are bound to loopback `127.0.0.1` and are never exposed publicly, access them via secure SSM port forwarding tunnels from your local machine:

### Forward Grafana (Port 3000 -> Localhost 8002):
```bash
aws ssm start-session \
    --region ap-south-1 \
    --target "$INSTANCE_ID" \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["3000"],"localPortNumber":["8002"]}'
```
*Open your browser at: `http://localhost:8002` (Login: `admin` / your SSM-retrieved password).*

### Forward Prometheus (Port 9090 -> Localhost 8001):
```bash
aws ssm start-session \
    --region ap-south-1 \
    --target "$INSTANCE_ID" \
    --document-name AWS-StartPortForwardingSession \
    --parameters '{"portNumber":["9090"],"localPortNumber":["8001"]}'
```
*Open your browser at: `http://localhost:8001`.*
