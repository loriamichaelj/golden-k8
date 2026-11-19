# Base ruleset. Cloud provider rulesets (aws, google, azurerm) are added
# with their adapters.
config {
  format = "compact"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}
