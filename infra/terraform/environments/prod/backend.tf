# Fill these in with the outputs from `infra/bootstrap` (state_bucket_name)
# and the table name you chose there, then run `terraform init`. This can't
# use variables - Terraform needs to know the backend before it evaluates
# anything else.
#
# terraform {
#   backend "s3" {
#     bucket         = "conduit-portfolio-tfstate-<your-suffix>"
#     key            = "prod/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "conduit-portfolio-tf-locks"
#     encrypt        = true
#   }
# }
