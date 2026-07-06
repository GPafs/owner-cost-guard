# outputs.tf — module contract surface.

output "validated_tags" {
  description = "The plan-time-validated accountability tags. Consumers apply these to governed resources."
  value       = var.tags
}

output "sns_topic_arn" {
  description = "ARN of the notification spine (ownership-attestation findings, budgets, anomaly alerts)."
  value       = aws_sns_topic.notifications.arn
}

output "budget_name" {
  description = "Name of the monthly cost budget."
  value       = aws_budgets_budget.monthly.name
}

output "ownership_lambda_arn" {
  description = "ARN of the ownership attestation Lambda."
  value       = aws_lambda_function.ownership.arn
}
