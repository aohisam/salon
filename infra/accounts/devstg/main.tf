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

  # === ここはあなたの GitHub に合わせて変更 ===
  github_org  = "aohisam"
  github_repo = "salon"

  # === 人間用ロールをAssumeできる主体（暫定） ===
  # 例：今あなたが使っている管理用IAMユーザー/ロールARNを入れる
  human_admin_principal_arns = [
    "arn:aws:iam::894923172428:user/tatsuya"
  ]

  # === envs の backend.tf から拾った値（あなたの現状に合わせ済み） ===
  dev_state_bucket = "tfstate-dev-my-saas-894923172428"
  dev_state_prefix = "envs/dev/"
  dev_state_kms_arn = "arn:aws:kms:ap-northeast-1:894923172428:key/1000dd13-1cfc-43a6-ace1-cb9b0aad4058"

  stg_state_bucket = "tfstate-stg-my-saas-894923172428"
  stg_state_prefix = "envs/stg/"
  stg_state_kms_arn = "arn:aws:kms:ap-northeast-1:894923172428:key/4e969044-269b-40fc-aa89-2d7360e08eae"

  tags_shared = { Project = local.project, Env = "shared", ManagedBy = "Terraform" }
  tags_dev    = { Project = local.project, Env = "dev",    ManagedBy = "Terraform" }
  tags_stg    = { Project = local.project, Env = "stg",    ManagedBy = "Terraform" }
}

provider "aws" {
  region = local.aws_region
}

# 既に OIDC Provider を作成済み、という前提で参照
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# -------------------------
# 人間用（暫定：指定PrincipalのみAssume可）
# -------------------------
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
  name   = "salon-devstg-readonly"

  assume_role_policy_json = data.aws_iam_policy_document.human_assume.json
  managed_policy_arns     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  tags                    = local.tags_shared
}

module "human_admin" {
  source = "../../modules/iam_role"
  name   = "salon-devstg-admin"

  assume_role_policy_json = data.aws_iam_policy_document.human_assume.json
  managed_policy_arns     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
  tags                    = local.tags_shared
}

# -------------------------
# GitHub OIDC trust
# plan  : PRのみ (sub = repo:ORG/REPO:pull_request)
# apply : environment別 (dev/stg)
# -------------------------
data "aws_iam_policy_document" "gh_pr" {
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
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${local.github_org}/${local.github_repo}:pull_request"]
    }
  }
}

data "aws_iam_policy_document" "gh_env_dev" {
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
      values   = ["repo:${local.github_org}/${local.github_repo}:environment:dev"]
    }
  }
}

data "aws_iam_policy_document" "gh_env_stg" {
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
      values   = ["repo:${local.github_org}/${local.github_repo}:environment:stg"]
    }
  }
}

# -------------------------
# stateアクセス（dev / stg を “それぞれのバケット&prefix” に限定）
# planでも state 更新が起きるので Put/Delete を含める
# -------------------------
data "aws_iam_policy_document" "tfstate_dev" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${local.dev_state_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${local.dev_state_prefix}*"]
    }
  }

  statement {
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.dev_state_bucket}/${local.dev_state_prefix}*"]
  }

  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [local.dev_state_kms_arn]
  }
}

data "aws_iam_policy_document" "tfstate_stg" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = ["arn:aws:s3:::${local.stg_state_bucket}"]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${local.stg_state_prefix}*"]
    }
  }

  statement {
    actions = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${local.stg_state_bucket}/${local.stg_state_prefix}*"]
  }

  statement {
    actions   = ["kms:Decrypt", "kms:Encrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
    resources = [local.stg_state_kms_arn]
  }
}

# -------------------------
# apply権限（ベストプラクティス：最初は“使うサービス中心に広め”、S3はstateだけ）
# 今後 Phase3+ で必要に応じて追加していく
# -------------------------
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

# -------------------------
# CI用ロール（dev）
# -------------------------
module "dev_plan" {
  source = "../../modules/iam_role"
  name   = "salon-dev-tf-plan"

  assume_role_policy_json = data.aws_iam_policy_document.gh_pr.json
  managed_policy_arns     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  inline_policies = {
    tfstate = data.aws_iam_policy_document.tfstate_dev.json
  }
  tags = local.tags_dev
}

module "dev_apply" {
  source = "../../modules/iam_role"
  name   = "salon-dev-tf-apply"

  assume_role_policy_json = data.aws_iam_policy_document.gh_env_dev.json
  inline_policies = {
    tfstate = data.aws_iam_policy_document.tfstate_dev.json
    apply   = data.aws_iam_policy_document.apply_services.json
  }
  tags = local.tags_dev
}

# -------------------------
# CI用ロール（stg）
# -------------------------
module "stg_plan" {
  source = "../../modules/iam_role"
  name   = "salon-stg-tf-plan"

  assume_role_policy_json = data.aws_iam_policy_document.gh_pr.json
  managed_policy_arns     = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
  inline_policies = {
    tfstate = data.aws_iam_policy_document.tfstate_stg.json
  }
  tags = local.tags_stg
}

module "stg_apply" {
  source = "../../modules/iam_role"
  name   = "salon-stg-tf-apply"

  assume_role_policy_json = data.aws_iam_policy_document.gh_env_stg.json
  inline_policies = {
    tfstate = data.aws_iam_policy_document.tfstate_stg.json
    apply   = data.aws_iam_policy_document.apply_services.json
  }
  tags = local.tags_stg
}

# -------------------------
# outputs（GitHub Variables にコピペする用）
# -------------------------
output "human_roles" {
  value = {
    readonly = module.human_readonly.role_arn
    admin    = module.human_admin.role_arn
  }
}

output "cicd_roles" {
  value = {
    dev_plan  = module.dev_plan.role_arn
    dev_apply = module.dev_apply.role_arn
    stg_plan  = module.stg_plan.role_arn
    stg_apply = module.stg_apply.role_arn
  }
}
