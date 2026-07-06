# The example is the deploy root: it configures AWS and plugs in the module.
# The module itself is provider-agnostic and inherits this configuration.
provider "aws" {
  region = var.region

  # Baseline operational tags applied to every resource. Distinct from the
  # validated accountability tags (owner / cost-center / environment).
  default_tags {
    tags = {
      ManagedBy = "Terraform"
      Project   = "ownership-n-cost-governance-example"
    }
  }

  # The attestation Lambda writes this tag out of band; without ignore_tags,
  # every plan would remove it from Terraform-managed resources.
  ignore_tags {
    keys = ["ownership:status"]
  }
}
