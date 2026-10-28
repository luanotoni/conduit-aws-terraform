# Conduit on AWS — legacy Django app, modernized and deployed production-grade

A real 2017 open-source Django app ([RealWorld/Conduit](https://github.com/gothinkster/django-realworld-example-app) —
a Medium.com clone), upgraded from Django 1.10 (EOL) to Django 5.2 LTS, and
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
 [ CloudFront ] ── HTTPS; React SPA from a private S3 bucket,
   │               /api/* proxied to the ALB (same origin → no CORS)
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
frontend/                 React/Redux RealWorld client, restyled
infra/terraform/modules/  network, database, ecs, waf, monitoring, logs, frontend, signoz
infra/terraform/environments/prod/   wires the modules together
infra/bootstrap/          one-time setup: GitHub OIDC role + TF state backend
.github/workflows/        ci.yml (test + plan), cd.yml (build + deploy), frontend.yml (SPA → S3/CloudFront)
scripts/deploy-frontend.sh  build the React frontend and publish it to S3/CloudFront
```

## What changed in the app during modernization

- Django 1.10 → 4.2 LTS (`django.conf.urls.url` → `re_path`, added
  `app_name` to each app's URLconf, fixed PyJWT 1.x → 2.x API changes)
- Hardcoded `SECRET_KEY`, `DEBUG=True`, SQLite → all environment-driven, with
  Postgres as the real backend (`app/conduit/settings.py`)
- Added `/healthz` for the ALB's target group health check
- Added WhiteNoise, gunicorn, structured JSON logging to stdout (→ CloudWatch)
- Django 4.2 → 5.2 LTS (4.2's remaining CVEs are only fixed on 5.2+)
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
curl "$(terraform output -raw frontend_url)/api/tags"
```
The ALB only accepts traffic from CloudFront, so curling `alb_dns_name`
directly times out. To debug the ALB on its own, apply with
`-var restrict_alb_to_cloudfront=false`.

### 4b. Publish the frontend
`frontend/` is the [RealWorld react-redux client](https://github.com/gothinkster/react-redux-realworld-example-app),
restyled. Add two more repository variables from the prod Terraform outputs:

| Variable | Value |
|---|---|
| `FRONTEND_BUCKET` | `terraform output -raw frontend_bucket_name` |
| `FRONTEND_DISTRIBUTION_ID` | `terraform output -raw frontend_distribution_id` |

From then on every push to `main` touching `frontend/` builds it and publishes
it (`.github/workflows/frontend.yml`). For a manual deploy from your machine:
`scripts/deploy-frontend.sh`. The site URL is `terraform output -raw frontend_url`.

The app always calls the API at `/api`; CloudFront forwards `/api/*` to the
ALB, so the browser only ever talks to one HTTPS origin. The frontend builds
with Vite (`npm run build` → `build/`, hashed assets under `build/static/`).

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

cd ../frontend
npm install && npm start   # http://localhost:4100, /api proxied to :8000
```
Set `API_PROXY_TARGET` to point the dev server's `/api` proxy somewhere else.

## Observability

- **Structured logs**: Django writes one JSON object per line. Every request
  logs a `request` event (`method`, `route`, `status`, `duration_ms`,
  `user_id`) and every line carries a `request_id` — the ALB's
  `X-Amzn-Trace-Id` when present, echoed back as the `X-Request-Id` response
  header, so a user-reported error can be traced to its log lines.
- **Metrics from logs**: CloudWatch metric filters turn those events into
  `Conduit/App` metrics (`Requests`, `Http5xx`, `RequestDuration`,
  `ErrorLogs`) — no agent or SDK in the container.
- **Alarms → SNS email**: availability SLO (more than 1% 5xx at the ALB for
  15 min), Django ERROR logs, plus the existing ECS/ALB/RDS alarms.
- **Dashboard**: alarm status, app request rate and latency percentiles,
  ECS, ALB, RDS (including connections), WAF allowed/blocked, CloudFront error
  rates, and a table of recent application errors.
- **Saved Logs Insights queries** (`conduit-prod/...`): errors, slowest routes
  (p95/p99), 4xx/5xx by route, trace one request by id, Postgres slow queries,
  rejected VPC flows.
- **More log sources**: Postgres log (queries over 500ms) exported to
  CloudWatch, VPC Flow Logs (REJECT only by default), and ALB + CloudFront
  access logs in an S3 bucket with 30-day expiry
  (`terraform output -raw access_logs_bucket`).
- **Distributed tracing → self-hosted SigNoz** (`modules/signoz`): Django and
  psycopg2 are instrumented with OpenTelemetry (`apps/core/tracing.py`) and
  export OTLP/HTTP to a SigNoz collector on a private EC2 instance (`m7i-flex.large`,
  ~US$70/month, `enable_signoz = false` turns it off). Every request becomes a
  trace with its SQL queries as child spans, and each JSON log line carries the
  `trace_id`, so a log line in CloudWatch leads straight to its trace.
  Health checks are excluded. CloudWatch stays the source of alarms.
  - Nothing is exposed outside the VPC: the collector only accepts the ECS
    tasks' security group on 4318, and the UI is reached over Session Manager:
    `terraform output -raw signoz_ui_command`, then open http://localhost:8080
    (the first visit creates the admin account).
  - The collector is found at `signoz.conduit.internal` (Route 53 private
    zone), so the task definition doesn't change when the instance does.
  - Installed on first boot with SigNoz's Foundry, with every binary pinned
    and SHA-256 checked (`user-data.sh.tftpl`, progress in
    `/var/log/cloud-init-output.log`). Data lives on the instance's EBS volume:
    it survives reboots and AWS host recovery, not a replacement.
  - Terraform ignores `container_definitions` after bootstrap, so enabling
    SigNoz on an already deployed stack also needs `OTEL_EXPORTER_OTLP_ENDPOINT`
    and `OTEL_RESOURCE_ATTRIBUTES` added to the live task definition once.

## Security scanning

Trivy runs on every PR (`ci.yml`: dependencies, secrets and Terraform/
Dockerfile misconfigurations) and on every deploy (`cd.yml`: the built image,
before it is pushed). Any HIGH/CRITICAL finding fails the job unless it is
accepted, with a written reason, in `.trivyignore.yaml`. Trivy is installed
from a pinned release verified by checksum (`scripts/install-trivy.sh`).
Run it locally with:
```bash
trivy fs --ignorefile .trivyignore.yaml --skip-dirs '**/node_modules' .
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
