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

# Rules for google_* resources (machine types, invalid values).
plugin "google" {
  enabled = true
  version = "0.41.0"
  source  = "github.com/terraform-linters/tflint-ruleset-google"
}

# Rules for azurerm_* resources (VM sizes, invalid values).
plugin "azurerm" {
  enabled = true
  version = "0.33.0"
  source  = "github.com/terraform-linters/tflint-ruleset-azurerm"
}
