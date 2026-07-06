# examples/complete — the live demo and the canonical deploy root.
#
# Deploys the governance control plane (via the module) plus two governed S3
# buckets that exercise the ownership outcomes:
#   - ok_demo    : owned by a CURRENT owner (alice)         -> Lambda flags `ok`
#   - stale_demo : owned by a VALID-BUT-EXPIRED owner (bob)  -> Lambda flags `stale`
# `orphaned` and the plan-time rejection are shown in this folder's README.

module "governance" {
  source = "../../"

  notification_email    = var.notification_email
  monthly_budget_amount = 100

  # Keep false on a first deploy; enable via terraform.tfvars once the keys
  # appear in billing data (~24h, payer account). See README.
  enable_cost_allocation_tags = var.enable_cost_allocation_tags

  # The validated tag set. An owner not in owners.yaml fails THIS plan — try
  # changing it to ghost@example.com (see README).
  tags = {
    owner       = "alice@example.com"
    cost-center = "cc-1001"
    environment = "dev"
  }
}

# Current owner -> `ok`. Carries the module's validated tags (the paved-road
# pattern: route your tags through the contract, then apply the result).
resource "aws_s3_bucket" "ok_demo" {
  bucket_prefix = "ownership-demo-ok-"
  tags          = module.governance.validated_tags
}

# Valid-but-expired owner (bob is in owners.yaml) -> `stale`. This still plans
# fine; staleness is a runtime check the Lambda performs, not a plan-time one.
resource "aws_s3_bucket" "stale_demo" {
  bucket_prefix = "ownership-demo-stale-"
  tags = {
    owner       = "bob@example.com"
    cost-center = "cc-1002"
    environment = "dev"
  }
}

# Keep the demo buckets private — a governance example shouldn't ship public
# buckets. (S3 also defaults to private + encrypted; this is belt-and-braces.)
resource "aws_s3_bucket_public_access_block" "demo" {
  for_each = {
    ok    = aws_s3_bucket.ok_demo.id
    stale = aws_s3_bucket.stale_demo.id
  }
  bucket = each.value

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
