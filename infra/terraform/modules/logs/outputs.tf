output "bucket_id" {
  value = aws_s3_bucket.this.id
}

output "bucket_domain_name" {
  description = "What CloudFront's logging_config expects"
  value       = aws_s3_bucket.this.bucket_domain_name
}
