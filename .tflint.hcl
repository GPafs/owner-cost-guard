# Run `tflint --init` once to install plugins, then `tflint`.
# Pin the aws ruleset version to the latest release as needed.

config {
  call_module_type = "all"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

plugin "aws" {
  enabled = true
  version = "0.38.0" # check github.com/terraform-linters/tflint-ruleset-aws/releases
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
