terraform {
  backend "s3" {
    bucket = "terraform-module-state-files"
    key    = "426857564226/dotnet_dev.tfstate"
    dynamodb_table = "adex-terraform-state"
    acl            = "bucket-owner-full-control"
    encrypt        = true
    region         = "us-east-1"
  }
}
