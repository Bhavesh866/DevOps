# Partial backend configuration: bucket/key/region are supplied per stack at
# init time so one root serves the shared stack and every dedicated tenant:
#   terraform init -backend-config=../../live/<stack>/backend.hcl
# CI validation uses `init -backend=false` and never touches state.
# S3 native locking (use_lockfile) requires Terraform >= 1.10; no DynamoDB table.
terraform {
  backend "s3" {
    encrypt      = true
    use_lockfile = true
  }
}
