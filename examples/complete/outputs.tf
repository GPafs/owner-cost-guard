# Handy references for verifying the deployment (used by the runbook).

output "ok_demo_bucket" {
  description = "Name of the bucket owned by a current owner (expect ownership:status = ok)."
  value       = aws_s3_bucket.ok_demo.bucket
}

output "stale_demo_bucket" {
  description = "Name of the bucket owned by an expired owner (expect ownership:status = stale)."
  value       = aws_s3_bucket.stale_demo.bucket
}

output "sns_topic_arn" {
  description = "Notification topic — subscribe/confirm to receive findings."
  value       = module.governance.sns_topic_arn
}

output "ownership_lambda_arn" {
  description = "The attestation Lambda — invoke it manually to run a check on demand."
  value       = module.governance.ownership_lambda_arn
}

output "budget_name" {
  description = "The monthly cost budget."
  value       = module.governance.budget_name
}
