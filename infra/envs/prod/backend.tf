terraform {
  backend "s3" {
    bucket         = "tfstate-prod-my-saas-581059493336"
    key            = "envs/prod/terraform.tfstate"
    region         = "ap-northeast-1"
    use_lockfile   = true
    encrypt        = true
    kms_key_id     = "arn:aws:kms:ap-northeast-1:581059493336:key/a4bebf8a-61ad-42e5-8c81-5620fdc25b22"
  }
}
