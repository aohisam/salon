terraform {
  backend "s3" {
    bucket         = "tfstate-stg-my-saas-894923172428"
    key            = "envs/stg/terraform.tfstate"
    region         = "ap-northeast-1"
    dynamodb_table = "tf-lock-stg-my-saas"
    encrypt        = true
    kms_key_id     = "arn:aws:kms:ap-northeast-1:894923172428:key/4e969044-269b-40fc-aa89-2d7360e08eae"
  }
}

