terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  aws_region = "ap-northeast-1"
  project    = "salon"

  github_org  = "aohisam"
  github_repo = "salon"

  human_admin_principal_arns = [
    "arn:aws:organizations::894923172428:account/o-6dcyp4ldka/581059493336"
  ]

  prod_state_bucket  = "tfstate-prod-my-saas-581059493336"
  prod_state_prefix  = "envs/prod/"
  prod_state_kms_arn = "arn:aws:kms:ap-northeast-1:581059493336:key/a4bebf8a-61ad-42e5-8c81-5620fdc25b22"

  tags_shared = { Project = local.project, Env = "shared", ManagedBy = "Terraform" }
  tags_prod   = { Project = local.project, Env = "prod",   ManagedBy = "Terraform" }
}

provider "aws" {
  region = local.aws_region
}

data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

data "aws_iam_policy_document" "human_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "AWS"
      identifiers = local.human_admin_principal_arns
    }
  }
}

module "human_readonly" {
  source = "../../modules/iam_role"
  name   = "salon-prod-readonly"

  assume_role_policy_json = data.aws_iam_policy_document.human_assume.json
  managed_policy_arns     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  tags                    = local.tags_shared
}

module "human_admin" {
  source = "../../modules/iam_role"
  name   = "salon-prod-admin"

  assume_role_policy_json = data.aws_iam_policy_document.human_assume.json
  managed_policy_arns     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  tags                    = local.tags_shared
}

# prod apply は environment:prod で縛る（あなたの workflow と一致）
data "aws_iam_policy_document" "gh_env_prod" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_org}/${local.github_repo}:environment:prod"]
    }
  }
}

data "aws_iam_policy_document" "tfstate_prod" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${local.prod_state_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${local.prod_state_prefix}*"]
    }
  }

  statement {
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.prod_state_bucket}/${local.prod_state_prefix}*"]
  }

  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [local.prod_state_kms_arn]
  }
}

data "aws_iam_policy_document" "apply_services" {
  statement {
    actions = [
      "sts:GetCallerIdentity",
      "iam:*",
      "cloudtrail:*",
      "budgets:*",
      "sns:*",
      "logs:*",
      "cloudwatch:*",
      "ec2:*",
      "elasticloadbalancing:*",
      "application-autoscaling:*",
      "autoscaling:*",
      "ecs:*",
      "ecr:*",
      "rds:*",
      "elasticache:*",
      "secretsmanager:*",
      "ssm:*",
      "lambda:*",
      "route53:*",
      "acm:*",
      "cloudfront:*",
      "wafv2:*",
      "kms:*",
      "tag:*"
    ]
    resources = ["*"]
  }
}

module "prod_apply" {
  source = "../../modules/iam_role"
  name   = "salon-prod-tf-apply"

  assume_role_policy_json = data.aws_iam_policy_document.gh_env_prod.json
  inline_policies = {
    tfstate = data.aws_iam_policy_document.tfstate_prod.json
    apply   = data.aws_iam_policy_document.apply_services.json
  }
  tags = local.tags_prod
}

output "human_roles" {
  value = {
    readonly = module.human_readonly.role_arn
    admin    = module.human_admin.role_arn
  }
}

output "cicd_roles" {
  value = {
    prod_apply = module.prod_apply.role_arn
  }
}
