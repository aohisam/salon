# salon (Infrastructure)

このリポジトリは salon の IaC（Infrastructure as Code）を Terraform で管理します。  
**「インフラ=コードが正」**を前提に、AWSコンソールの手作業を原則禁止し、PRベースで変更します。

## 環境
- dev
- stg
- prod（本番は **別AWSアカウント**）

リージョン: `ap-northeast-1`

## ディレクトリ構成
- `infra/bootstrap/`
  - Terraform の state を置くための **S3 + KMS** を作る（初期基盤）
  - bootstrap は “state置き場を作る作業” なので **例外的にローカル実行OK（基本1回）**
- `infra/envs/`
  - 各環境の “組み立て” ディレクトリ（**環境ごとに state 分離**）
  - `dev/`, `stg/`, `prod/`
- `infra/modules/`
  - 再利用する Terraform module

## Terraform state（台帳）の考え方
- state は **S3 backend** に保存する（ローカルに常駐させない）
- state は **SSE-KMS** で暗号化される（復号できる主体をKMS権限で制御）
- ロックは **S3のロックファイル方式（use_lockfile）** を使用
  - 以前の `dynamodb_table` は非推奨方向（Terraform側でdeprecated扱い）なので使いません 

## 運用ルール（最重要）
- **ローカルから `terraform apply` は原則禁止**
  - 例外: `infra/bootstrap/*` の初回構築/更新（必要時のみ）
- 変更手順は必ずこれ：
  1. ブランチ作成
  2. PR作成（CIが fmt/validate/plan を実行）
  3. レビュー
  4. mainへmerge
  5. CIが apply
     - dev/stg: 自動
     - prod: GitHub Environments の承認後に実行（Required reviewers）

## CI/CD（GitHub Actions）
- PR時:
  - `terraform fmt -check`
  - `terraform validate`
  - `terraform plan`（dev/stg）
  - planは **PRコメント** と **artifact** で確認できる
- main merge時:
  - dev/stg は自動 `apply`
  - prod は Environment 承認後に `apply`

## 命名/タグ
- 主要タグ:
  - `Project`, `Env`, `ManagedBy=Terraform`
- リソース名には `project/env/region` を含める方針（環境誤爆を防ぐ）

## 例外対応（break-glass）
- 緊急時は管理者のみが一時的に操作できる（最小限の権限）
- ただし復旧後は Terraform に反映して「コードが正」に戻す