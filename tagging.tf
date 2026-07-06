# tagging.tf — plan-time tag contract + cost-allocation activation.
# var.tags is validated so `terraform plan` fails on a missing required key, an
# environment outside dev|staging|prod, or an owner not in the registry. The
# failure happens before any AWS call, so the negative test needs no credentials.

locals {
  # Also the cost-allocation schema. The validations below re-list these inline
  # because variable validation cannot reference locals.
  required_tag_keys = ["owner", "cost-center", "environment"]
}

variable "tags" {
  description = <<-EOT
    Accountability tags applied to governed resources, validated at plan time.
    Must include: owner (must resolve to an id in owners_file), cost-center,
    and environment (one of dev|staging|prod). Surfaced to consumers via the
    validated_tags output.
  EOT
  type        = map(string)

  # Required keys present (cost-center value checks live in the cost consumer).
  validation {
    condition = alltrue([
      for key in ["owner", "cost-center", "environment"] : contains(keys(var.tags), key)
    ])
    error_message = "tags must include all required keys: owner, cost-center, environment."
  }

  validation {
    condition     = contains(["dev", "staging", "prod"], lookup(var.tags, "environment", ""))
    error_message = "tags[\"environment\"] must be one of: dev, staging, prod."
  }

  # owner resolves to an id in the registry. Repeats main.tf's path resolution
  # inline — validation cannot reference locals.
  validation {
    condition = contains(
      [for owner in yamldecode(file(coalesce(var.owners_file, "${path.module}/owners.yaml"))).owners : owner.id],
      lookup(var.tags, "owner", "")
    )
    error_message = "tags[\"owner\"] must resolve to an id in the ownership registry (owners_file)."
  }
}

# Activate the schema keys as cost-allocation tags. Requires the payer account
# and that the keys have appeared in billing data (~24h) — see enable_cost_allocation_tags.
resource "aws_ce_cost_allocation_tag" "schema" {
  for_each = var.enable_cost_allocation_tags ? toset(local.required_tag_keys) : toset([])

  tag_key = each.value
  status  = "Active"
}
