# Applied manually, once, before the CI/CD pipeline exists - by definition
# the pipeline can't create the very IAM role it needs in order to run.
#
#   cd infra/bootstrap
#   terraform init
#   terraform apply -var='github_repo=your-github-username/your-repo-name'
#
# After this, GitHub Actions authenticates to AWS via short-lived OIDC tokens
# instead of a long-lived access key sitting in repo secrets.

terraform {
  required_version = ">= 1.7"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "github_repo" {
  description = "e.g. 'yourusername/conduit-aws-portfolio' - the role can only be assumed from workflows in this exact repo"
  type        = string
}

variable "state_bucket_name" {
  description = "S3 bucket for Terraform remote state - must be globally unique"
  type        = string
}

variable "state_lock_table_name" {
  type    = string
  default = "conduit-portfolio-tf-locks"
}

data "aws_caller_identity" "current" {}

# --- Remote state backend -----------------------------------------------------
# Created here, before anything else, so the "prod" environment can point its
# backend.tf at this bucket from the very first `terraform init`.

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "tf_locks" {
  name         = var.state_lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# --- GitHub OIDC provider ------------------------------------------------------
# Thumbprints are GitHub's well-known OIDC intermediate CA thumbprints
# (documented in GitHub's own OIDC hardening guide). AWS also independently
# validates the certificate chain itself, so this list mainly needs to exist,
# not be perfectly current.

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
}

# --- Role the CI/CD pipeline assumes --------------------------------------------

data "aws_iam_policy_document" "github_actions_assume_role" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      # Any branch/PR/tag in this one repo - not "any repo in the org", and
      # not scoped to only `main` because the CI workflow also needs this role
      # to run `terraform plan` on pull requests from branches.
      values = ["repo:${var.github_repo}:*"]
    }
  }
}

resource "aws_iam_role" "github_actions" {
  name               = "github-actions-conduit-deploy"
  assume_role_policy = data.aws_iam_policy_document.github_actions_assume_role.json
}

# Scoped to the services this project actually touches. Broader than
# textbook least-privilege (mainly the ec2:*/iam:* actions, which are
# genuinely hard to scope tightly for Terraform-managed VPC + ECS IAM roles)
# but far short of AdministratorAccess. Document this trade-off explicitly if
# you reuse this for a real client project instead of a portfolio piece.
data "aws_iam_policy_document" "github_actions_permissions" {
  statement {
    sid    = "InfrastructureServices"
    effect = "Allow"
    actions = [
      "ec2:*",
      "ecs:*",
      "ecr:*",
      "elasticloadbalancing:*",
      "rds:*",
      "wafv2:*",
      "cloudwatch:*",
      "logs:*",
      "secretsmanager:*",
      "sns:*",
      "application-autoscaling:*",
      "tag:GetResources",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "IamForEcsRoles"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PassRole",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
    ]
    resources = [
      "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/conduit-*",
    ]
  }

  statement {
    sid     = "StateBackend"
    effect  = "Allow"
    actions = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [
      aws_s3_bucket.tf_state.arn,
      "${aws_s3_bucket.tf_state.arn}/*",
    ]
  }

  statement {
    sid       = "StateLock"
    effect    = "Allow"
    actions   = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.tf_locks.arn]
  }
}

resource "aws_iam_role_policy" "github_actions" {
  name   = "conduit-deploy-permissions"
  role   = aws_iam_role.github_actions.id
  policy = data.aws_iam_policy_document.github_actions_permissions.json
}

output "role_arn" {
  description = "Put this in the GitHub repo as a variable/secret: AWS_DEPLOY_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "state_bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}
