locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # AWS-managed CloudFront policies.
  cache_policy_optimized         = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
  cache_policy_disabled          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" # Managed-CachingDisabled
  origin_request_all_except_host = "b689b0a8-53d0-40ab-baf2-68738e2966ac" # Managed-AllViewerExceptHostHeader

  s3_origin_id  = "frontend-s3"
  alb_origin_id = "api-alb"
}

# --- Bucket holding the React build (private; only CloudFront can read it) ---

resource "aws_s3_bucket" "this" {
  bucket_prefix = "${local.name_prefix}-frontend-"
  force_destroy = true # it's a build artifact; `terraform destroy` should just work

  tags = { Name = "${local.name_prefix}-frontend" }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket                  = aws_s3_bucket.this.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${local.name_prefix}-frontend"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

data "aws_iam_policy_document" "bucket" {
  statement {
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# --- SPA routing ----------------------------------------------------------------
# React Router uses real paths (/article/foo, /@user). S3 has no such objects,
# so rewrite anything that isn't a static asset to /index.html. Done here rather
# than with distribution-wide custom error responses, which would also turn the
# API's own 403/404 JSON responses into index.html.

resource "aws_cloudfront_function" "spa_rewrite" {
  name    = "${local.name_prefix}-spa-rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;
      var isAsset = uri.indexOf('/static/') === 0 ||
        /^\/[^\/]+\.(ico|css|js|json|png|svg|txt|map)$/.test(uri);
      if (!isAsset) {
        request.uri = '/index.html';
      }
      return request;
    }
  EOT
}

# --- Distribution: SPA from S3, /api/* proxied to the ALB --------------------------
# Serving both from one HTTPS origin means no mixed-content blocking (the ALB is
# HTTP-only until there's a domain + ACM cert) and no CORS at all.

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix} frontend + API"
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # NA + EU edges only; cheapest

  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  origin {
    origin_id   = local.alb_origin_id
    domain_name = var.alb_dns_name

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id       = local.s3_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = local.cache_policy_optimized

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_rewrite.arn
    }
  }

  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = local.alb_origin_id
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    cache_policy_id        = local.cache_policy_disabled
    # Forwards Authorization, query strings, etc. but keeps Host as the ALB's
    # DNS name, which is what Django's ALLOWED_HOSTS expects.
    origin_request_policy_id = local.origin_request_all_except_host
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = { Name = "${local.name_prefix}-frontend" }
}
