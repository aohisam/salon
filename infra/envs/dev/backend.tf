terraform {
  backend "s3" {
    bucket         = "tfstate-dev-my-saas-894923172428"
    key            = "envs/dev/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "tf-lock-dev-my-saas"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:ap-northeast-1:894923172428:key/1000dd13-1cfc-43a6-ace1-cb9b0aad4058"
  }
}
