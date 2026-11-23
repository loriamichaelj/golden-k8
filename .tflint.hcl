# Base ruleset plus one ruleset per cloud adapter. Plugin versions are pinned;
# `tflint --init` downloads them (set GITHUB_TOKEN to avoid API rate limits).
config {
  format = "compact"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Rules for aws_* resources (instance types, IAM, invalid values).
plugin "aws" {
  enabled = true
  version = "0.50.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
