# EventPass EKS Capstone

A teaching app for the capstone: deploy an online ticketing and event-management service to Amazon EKS, use private Amazon RDS for MySQL, and automate builds and releases with GitHub Actions.

**AWS resources are not created until you run the Terraform setup.** EKS, worker nodes, RDS, NAT Gateway, Secrets Manager, ECR storage, and the Application Load Balancer can all incur charges. Check current prices for your region, run the lab only when needed, and use the destroy runbook after class.

## What students will see

- An event catalogue, mock ticket reservations, and a password-protected organizer page.
- A container image built from a Git commit and stored in Amazon ECR.
- A Kubernetes Deployment and Service in a dedicated `eventpass` namespace.
- A temporary public HTTP URL served by an ALB created from Kubernetes Ingress.
- A private MySQL database in RDS. The app does not accept payment or collect attendee personal information.
- CI on pull requests and automatic deploys after a passing commit reaches `main`.

The app is a classroom demonstration, not production ticketing software. Use a throwaway organizer password. The public ALB serves HTTP in this low-complexity lab, so do not enter real credentials or personal data.

## Architecture and staged lesson plan

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the topology, tradeoffs, and stage checkpoints.

1. **App + local MySQL:** run the app with Docker Compose; demonstrate event listing and atomic ticket reservation.
2. **AWS foundation:** Terraform creates a VPC, EKS, one managed node, ECR, private single-AZ RDS, and a GitHub OIDC deployment role.
3. **Kubernetes and ingress:** inspect namespace RBAC, Deployment probes, Service, Ingress, and the AWS Load Balancer Controller.
4. **Automated delivery:** make a code change, open a pull request, merge to `main`, then follow the Actions run from test to ECR to EKS rollout.
5. **Reuse:** destroy the environment and repeat the setup for another class.

## Stage 1: run locally

Prerequisites: Docker Desktop with Compose.

1. Copy `.env.example` to `.env` and replace the example password and secret key.
2. Run:

   ```powershell
   docker compose up --build
   ```

3. Open `http://localhost:8080`; reserve a ticket and see the remaining count change. Open `/organizer` and sign in as `admin` using the `ADMIN_PASSWORD` in `.env`. `/healthz` checks MySQL.
4. Stop with `Ctrl+C`. `docker compose down` preserves the local MySQL volume. For a disposable reset, run `docker compose down --volumes`.

## Prerequisites for AWS stages

Install and configure these tools on the instructor workstation:

- AWS CLI v2 with an IAM identity allowed to create the Terraform resources and pass EKS/IAM roles.
- Terraform 1.5.7 or later.
- `kubectl`, Helm 3, and `eksctl`.
- Docker Desktop, Git, and a public GitHub repository.
- GitHub Actions enabled for the repository.

This repository defaults to `ap-south-1` (Mumbai), EKS Kubernetes `1.36`, one `t3.medium` node, and single-AZ `db.t3.micro` MySQL. RDS uses the regional default MySQL engine version unless you set an exact supported version in `terraform/terraform.tfvars`. Confirm the selected instance types, database engine version, and Kubernetes version are offered in your chosen region and account quotas before applying. The VPC uses two AZs but one NAT Gateway to reduce the lab footprint; this is not a highly available production topology.

## Stage 2: configure the GitHub OIDC trust and create AWS resources

1. Create this project as a **public** repository named `eventpass-eks-capstone` under your GitHub account. Push the repository's `main` branch.
2. Retrieve GitHub's immutable IDs (required by GitHub for repositories created after July 15, 2026):

   ```powershell
   .\scripts\get-github-ids.ps1 -Owner YOUR_GITHUB_USER -Repository eventpass-eks-capstone
   ```

3. Copy `terraform/terraform.tfvars.example` to `terraform/terraform.tfvars`. Enter your GitHub owner name and both numeric IDs. Keep `terraform.tfvars` private; it is ignored by Git.
4. From the repository root, start the infrastructure setup:

   ```powershell
   .\scripts\start-lab.ps1
   ```

   The script initializes Terraform and shows a plan. Review every resource, check current prices with the AWS Pricing Calculator, and type `CREATE` only when you are ready to provision. The script installs the AWS Load Balancer Controller and creates the app namespace and restricted deploy RoleBinding after EKS is ready.

Terraform state is local under `terraform/` and is ignored by Git. Keep the same state directory for every apply and destroy. Losing that state can make cleanup harder.

## Stage 3: configure GitHub Actions

In the GitHub repository, open **Settings → Secrets and variables → Actions**. Add these repository variables using Terraform outputs:

| Variable | Value |
| --- | --- |
| `AWS_REGION` | `terraform output -raw aws_region` |
| `AWS_DEPLOY_ROLE_ARN` | `terraform output -raw github_deployer_role_arn` |
| `EKS_CLUSTER_NAME` | `terraform output -raw cluster_name` |
| `ECR_REPOSITORY` | `eventpass` |
| `DB_HOST` | `terraform output -raw rds_endpoint` |
| `DB_NAME` | `terraform output -raw rds_database_name` |
| `DB_SECRET_ARN` | `terraform output -raw rds_secret_arn` |

Create two **Actions secrets** named `ADMIN_PASSWORD` and `SECRET_KEY`. Use a unique, temporary organizer password and a long random Flask secret key. Do not put either value in Git, Terraform variables, ConfigMaps, or repository variables.

The pipeline tests every pull request. On a push to `main`, it assumes the Terraform-created AWS role through OIDC, builds an image tagged with the commit SHA, pushes it to ECR, creates the runtime ConfigMap and refreshes Kubernetes secrets from RDS Secrets Manager and GitHub Actions secrets, applies the Kustomize overlay, and waits for the Deployment rollout. The AWS role is scoped to this repository's immutable GitHub IDs and the EKS deployer group is bound only in the `eventpass` namespace.

## Stage 4: use and teach the deployment

After the first successful deployment, get the public URL:

```powershell
kubectl get ingress eventpass -n eventpass
```

Open the ADDRESS shown by Kubernetes. It may take a few minutes for the ALB to become active. Show students:

```powershell
kubectl get pods,services,ingress -n eventpass
kubectl describe ingress eventpass -n eventpass
kubectl logs deployment/eventpass -n eventpass
kubectl rollout history deployment/eventpass -n eventpass
```

The deployer is namespaced and cannot administer cluster-wide resources. The ALB Controller runs in `kube-system` with its own IAM role. AWS credentials are short-lived; no static AWS access key is stored in GitHub.

## Stage 5: destroy after class

Run this from the repo root:

```powershell
.\scripts\destroy-lab.ps1
```

The script removes the app namespace first so the controller can delete its ALB, removes the controller's IRSA role and policy, then runs `terraform destroy`. Terraform is configured to skip the final RDS snapshot and allow ECR deletion: **the database and its data are permanently discarded**. Confirm in AWS that the EKS cluster, RDS DB instance, NAT Gateway, and load balancers are gone. Keep the local Terraform state until cleanup is confirmed.

## Troubleshooting checkpoints

- `terraform plan` fails on a DB class/version: change `db_instance_class` or `mysql_engine_version` to one supported in the selected region, then rerun the plan.
- Nodes cannot pull ECR images: check that the node group is in private subnets and the NAT Gateway routes are healthy.
- GitHub gets `AccessDenied` for `AssumeRoleWithWebIdentity`: recheck the owner/repository IDs in `terraform.tfvars`, that the workflow runs from `main`, and that its deploy job has `id-token: write`.
- GitHub gets EKS authorization errors: check the EKS access entry, the `eventpass-deployer` group RoleBinding, and the namespace exists.
- Ingress has no address: check the controller pods/logs in `kube-system`, public subnet tags, and Ingress events.
- Pods do not become ready: inspect `kubectl describe pod`, app logs, the RDS endpoint/secret, and the RDS security-group rule.

## Repository map

| Path | Purpose |
| --- | --- |
| `app/` | Flask application, templates, and styles |
| `tests/` | CI tests against MySQL |
| `Dockerfile`, `docker-compose.yml` | Container and local preview |
| `terraform/` | VPC, EKS, RDS, ECR, OIDC, and IAM resources |
| `k8s/` | Namespace RBAC, Deployment, Service, Ingress, and classroom overlay |
| `.github/workflows/pipeline.yml` | Pull request checks and automated deployment |
| `scripts/` | Windows PowerShell setup, ALB controller bootstrap, ID lookup, and teardown |
| `docs/ARCHITECTURE.md` | Architecture and lesson checkpoints |
