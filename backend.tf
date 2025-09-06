terraform {
  backend "s3" {
    bucket         = "my-terraform-states-workspace"
    key            = "3tier/terraform.tfstate"
    region         = "us-west-2"
    dynamodb_table = "terraform-locks"
    encrypt        = true
  }
}
