# salon

・環境：dev / stg / prod

・分離方式：
　prodは別AWSアカウント

・リージョン：ap-northeast-1

・プロジェクト識別子（短いslug）：例 my-salon

・Terraform実行方針：
　・bootstrapのみ例外でローカル実行可（1回）
　・それ以外は PR → CI plan → main merge → CI apply

・state命名規約（例）：tfstate-<env>-<project>-<account_id>
