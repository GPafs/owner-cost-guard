terraform {
  # >= 1.9: input-variable validation can reference other variables, which the
  # tag contract uses to validate `owner` against the registry (owners_file)
  # and to fail the plan with zero AWS calls. Also covers terraform test (1.6+).
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source = "hashicorp/aws"
      # Pessimistic on the v6 major line (resolved to 6.51.0); allows minor/patch
      # but blocks a breaking 7.0. Exact build locked in .terraform.lock.hcl (committed).
      version = "~> 6.0"
    }
    # Packages the ownership Lambda into a deployment zip at plan time.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}
