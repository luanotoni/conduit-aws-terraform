#!/usr/bin/env bash
# Build the React frontend and publish it to the S3 bucket behind CloudFront.
#
#   scripts/deploy-frontend.sh [path-to-frontend]   (default: ~/frontend-demo)
#
# Bucket and distribution come from the prod Terraform outputs. The build calls
# the API at the relative path /api, which CloudFront proxies to the ALB.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FRONTEND_DIR="$(cd "${1:-$HOME/frontend-demo}" && pwd)"
TF_DIR="$REPO_ROOT/infra/terraform/environments/prod"

BUCKET="$(terraform -chdir="$TF_DIR" output -raw frontend_bucket_name)"
DISTRIBUTION_ID="$(terraform -chdir="$TF_DIR" output -raw frontend_distribution_id)"
FRONTEND_URL="$(terraform -chdir="$TF_DIR" output -raw frontend_url)"

echo "Building $FRONTEND_DIR"
cd "$FRONTEND_DIR"
[ -d node_modules ] || npm ci
REACT_APP_API_ROOT=/api npm run build

# Fingerprinted assets never change under the same name: cache them for a year.
aws s3 sync build/static "s3://$BUCKET/static" --delete \
  --cache-control "public, max-age=31536000, immutable"

# Everything else (index.html, theme.css, ...) must be revalidated so a deploy
# shows up immediately.
aws s3 sync build "s3://$BUCKET" --delete --exclude "static/*" \
  --cache-control "no-cache"

aws cloudfront create-invalidation --distribution-id "$DISTRIBUTION_ID" \
  --paths "/*" --query 'Invalidation.Id' --output text

echo "Deployed: $FRONTEND_URL"
