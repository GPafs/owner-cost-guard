# main.tf — load and index the ownership registry.
# The single owner-resolution seam: a future identity source (IAM Identity
# Center, CMDB, ...) would change only how owners_by_id is produced.

locals {
  # Caller-supplied registry path, or the module's bundled owners.yaml.
  owners_path = coalesce(var.owners_file, "${path.module}/owners.yaml")
  raw_owners  = yamldecode(file(local.owners_path)).owners

  # Indexed by owner id for membership lookups.
  owners_by_id = { for owner in local.raw_owners : owner.id => owner }

  owner_tag_key  = "owner"
  status_tag_key = "ownership:status" # written by the Lambda, never by consumers
}

# Shared account/partition/region lookups used when building IAM/KMS/SNS policies.
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}
