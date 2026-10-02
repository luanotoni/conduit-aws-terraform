# Conduit on AWS — legacy Django app, modernized and deployed production-grade

A real 2017 open-source Django app ([RealWorld/Conduit](https://github.com/gothinkster/django-realworld-example-app) —
a Medium.com clone), upgraded from Django 1.10 (EOL) to Django 4.2 LTS, and
deployed to AWS with the same infrastructure pattern used in real
migrations like [YSA Solutions' monolith-to-Fargate rebuild](https://aws.amazon.com/solutions/case-studies/ysa-solutions/):
Terraform-managed ECS Fargate, RDS Postgres Multi-AZ, an ALB, WAF, and a
GitHub Actions CI/CD pipeline that authenticates to AWS with no long-lived
credentials at all.

**Honest scope note:** Conduit itself is a simple CRUD blog API — it doesn't
*need* multi-AZ/autoscaling/WAF to handle a portfolio project's traffic. This
was built at production scale on purpose, to demonstrate the pattern, not
because the app demanded it.

## Architecture

```
Internet
   │
   ▼
 [ WAF ]  AWS-managed rule sets + rate limiting
   │
   ▼
 [ ALB ] ── public subnets (2 AZs)
   │
   ▼
 [ ECS Fargate service ] ── private subnets (2 AZs)
   │  2-6 tasks, autoscaled on CPU
   ▼
 [ RDS Postgres, Multi-AZ ] ── private subnets
```

Supporting pieces: ECR (image registry), Secrets Manager (DB credentials +
Django secret key — never in the task definition as plaintext), CloudWatch
(logs, alarms, dashboard), SNS (alarm → email).

## Repo layout

```
app/                      Django app (RealWorld/Conduit, modernized)
infra/terraform/modules/  network, database, ecs, waf, monitoring
infra/terraform/environments/prod/   wires the modules together
infra/bootstrap/          one-time setup: GitHub OIDC role + TF state backend
.github/workflows/        ci.yml (test + plan), cd.yml (build + deploy)
```

## What changed in the app during modernization

- Django 1.10 → 4.2 LTS (`django.conf.urls.url` → `re_path`, added
  `app_name` to each app's URLconf, fixed PyJWT 1.x → 2.x API changes)
- Hardcoded `SECRET_KEY`, `DEBUG=True`, SQLite → all environment-driven, with
  Postgres as the real backend (`app/conduit/settings.py`)
- Added `/healthz` for the ALB's target group health check
- Added WhiteNoise, gunicorn, structured logging to stdout (→ CloudWatch)
- Added the test suite — the original repo shipped with zero tests

## Setup — do this once, in order

### 0. Prerequisites
- AWS account (ideally a fresh one, or at least one you don't mind an
  experimental Budget alert on)
- **Set an AWS Budget alert before anything else.** RDS Multi-AZ + 2 NAT
  Gateways + WAF is *not* free-tier — expect roughly $80-120/mo if left
  running. This is a portfolio project: build it, demo it, `terraform
  destroy` it (see step 5).
- Terraform >= 1.7, Docker, AWS CLI v2, an IAM user with enough access to
  bootstrap (or just use root credentials once, locally, only for step 1)

### 1. Bootstrap: OIDC role + Terraform state backend
```bash
cd infra/bootstrap
terraform init
terraform apply \
  -var="github_repo=your-github-username/your-repo-name" \
  -var="state_bucket_name=conduit-portfolio-tfstate-$(whoami)-$RANDOM"
```
Note the two outputs: `role_arn` and `state_bucket_name`.

### 2. Point the prod environment at that backend
Edit `infra/terraform/environments/prod/backend.tf`, uncomment the block,
fill in the bucket name and region from step 1, then:
```bash
cd infra/terraform/environments/prod
terraform init
cp terraform.tfvars.example terraform.tfvars   # fill in your alert_email
terraform apply
```
This takes 10-15 minutes (RDS is the slow part). Note the outputs, especially
`alb_dns_name`, `ecr_repository_url`, `ecs_cluster_name`, `ecs_service_name`.

**Check your inbox** — SNS sends a subscription-confirmation email. Click it,
or alarms fire into the void.

The task definition boots with an `:bootstrap` placeholder image tag that
doesn't exist yet, so the ECS service will show 0 healthy tasks. That's
expected — the first real image comes from the pipeline in step 4.

### 3. Configure GitHub
In the repo's **Settings → Secrets and variables → Actions → Variables**, add:

| Variable | Value |
|---|---|
| `AWS_REGION` | e.g. `us-east-1` |
| `AWS_DEPLOY_ROLE_ARN` | `role_arn` output from step 1 |
| `ECR_REPOSITORY` | repo name portion of `ecr_repository_url` (e.g. `conduit-prod`) |
| `ECS_CLUSTER` | `ecs_cluster_name` output |
| `ECS_SERVICE` | `ecs_service_name` output |
| `ECS_TASK_DEFINITION_FAMILY` | `ecs_task_definition_family` output |
| `PRIVATE_SUBNET_IDS` | comma-separated, no spaces, e.g. `subnet-abc,subnet-def` (`terraform output -raw` on the network module, or check the VPC console) |
| `ECS_TASKS_SECURITY_GROUP_ID` | from the ECS module's `ecs_tasks_security_group_id` output |
| `ALERT_EMAIL` | same address as `terraform.tfvars` |
| `CORS_ALLOWED_ORIGINS` | Exact origin of the separately deployed frontend, e.g. `https://frontend.example.com` (no trailing slash) |

No secrets needed for AWS auth — that's the point of OIDC.

### 4. Push to trigger the first real deploy
```bash
git add . && git commit -m "Initial deploy" && git push origin main
```
Watch the **Actions** tab: it builds the image, pushes to ECR, runs
migrations as a one-off task, then updates the service. Once it's green:
```bash
curl http://<alb_dns_name>/healthz
```

### 5. Tear it down when you're done demoing
```bash
cd infra/terraform/environments/prod && terraform destroy
cd ../../bootstrap && terraform destroy   # only after prod is fully gone
```
Then check the console for anything orphaned — Elastic IPs and EBS volumes
occasionally survive a destroy and quietly keep billing.

## Local development
```bash
cd app
docker compose up --build
curl http://localhost:8000/healthz
```

## Notes on deliberate design decisions (good material for the writeup)

- **Migrations run as a one-off ECS task, not on container boot.** If
  `migrate` ran in the entrypoint, an autoscaling event launching 3 tasks at
  once would race 3 concurrent migration runs against the same database.
- **ECR is immutable-tagged.** Every deploy is tagged with the git SHA;
  nothing is ever pushed to a floating `latest`.
- **The DB security group and the ECS tasks security group don't reference
  each other directly** — the ingress rule connecting them lives in the root
  module, avoiding a circular dependency between the two child modules.
- **GitHub Actions authenticates via OIDC**, not a static AWS access key
  sitting in repo secrets — the token is short-lived and scoped to this one
  repo.
- **`terraform apply` never fights the pipeline for the running image**: the
  task definition's `container_definitions` is under `lifecycle {
  ignore_changes }` in Terraform, since the CD pipeline registers new
  revisions directly via the AWS CLI.

## Suggested LinkedIn post structure

1. **The pattern**: a common real-world scenario (cite the case study that
   inspired this — YSA Solutions, Vidsy, or similar) — legacy monolith,
   manual deploys, no IaC.
2. **What you actually built**: modernized a real 2017 Django app, then gave
   it the same infrastructure shape used in production migrations at that
   scale — Terraform, ECS Fargate, autoscaling, WAF, full CI/CD via OIDC.
3. **Something you can show, not just tell**: a screenshot/GIF of a task
   dying and ECS self-healing, or the CloudWatch alarm firing when you forced
   an error.
4. **The honest caveat**: this app didn't need this much infrastructure —
   you built it this way to demonstrate you can design for scale when a
   real system requires it.
5. Link to the repo.
