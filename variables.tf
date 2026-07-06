# Module input variables.
#
# This module is provider-agnostic: it declares no provider block and inherits
# AWS configuration (region, credentials, default_tags) from the root that uses
# it. See examples/complete for a working root.

variable "owners_file" {
  description = <<-EOT
    Path to the ownership registry YAML, the flat-file identity source used by
    the plan-time gate and the attestation Lambda. Each entry needs id, team,
    cost_center, attested_on (ISO date), and valid_for_days. Defaults to the
    module's bundled owners.yaml; pass a path from the calling configuration
    (e.g. abspath("owners.yaml")) to supply your own registry.
  EOT
  type        = string
  default     = null
}

variable "name_prefix" {
  description = "Prefix for named resources (SNS topic, KMS alias, ...). Ownership-first, combining both governance concerns."
  type        = string
  default     = "ownership-n-cost-governance"
  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]{1,40}$", var.name_prefix))
    error_message = "name_prefix must be 2-41 chars: lowercase letters, digits, and hyphens, starting alphanumeric."
  }
}

variable "notification_email" {
  description = "Email subscribed to the SNS notification topic. The recipient must confirm via the link AWS sends before alerts are delivered."
  type        = string
  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.notification_email))
    error_message = "notification_email must be a valid email address (e.g. alerts@example.com)."
  }
}

variable "monthly_budget_amount" {
  description = "Monthly cost budget limit, in USD."
  type        = number
  validation {
    condition     = var.monthly_budget_amount > 0
    error_message = "monthly_budget_amount must be greater than 0."
  }
}

variable "budget_thresholds" {
  description = "Budget notification thresholds, as a percent of the limit, for actual and forecasted spend."
  type = object({
    actual_warning   = number
    actual_critical  = number
    forecast_warning = number
  })
  default = {
    actual_warning   = 80
    actual_critical  = 100
    forecast_warning = 100
  }
}

variable "enable_cost_anomaly_detection" {
  description = "Toggle the Cost Anomaly Detection monitor + subscription (free, ML-based spike detection). Uses a custom, account-scoped monitor, so it coexists with the account's default monitor."
  type        = bool
  default     = true
}

variable "enable_cost_allocation_tags" {
  description = "Toggle activation of the schema keys as cost-allocation tags. Requires the management/payer account and that the keys have already appeared in billing data (~24h); leave off on fresh/standalone accounts."
  type        = bool
  default     = true
}

variable "anomaly_impact_threshold" {
  description = "Minimum absolute anomaly impact, in USD, that triggers a Cost Anomaly Detection alert."
  type        = number
  default     = 100
}

variable "ownership_schedule" {
  description = "EventBridge Scheduler expression for the ownership attestation run (cron/rate/at)."
  type        = string
  default     = "cron(0 7 * * ? *)" # daily 07:00 UTC
  validation {
    condition     = can(regex("^(cron|rate|at)\\(", var.ownership_schedule))
    error_message = "ownership_schedule must be a cron(), rate(), or at() expression."
  }
}

variable "tag_resource_types" {
  description = "Resource-type filters the attestation Lambda evaluates (e.g. [\"s3\"]). Empty = all taggable resources."
  type        = list(string)
  default     = []
}

variable "governed_tagging_actions" {
  description = "Service tagging permissions the Lambda may use to write the ownership:status tag. Defaults to S3; add each governed service's action (e.g. ec2:CreateTags, rds:AddTagsToResource) to extend write-back. The written key is constrained to ownership:status regardless."
  type        = list(string)
  default     = ["s3:GetBucketTagging", "s3:PutBucketTagging"]
}

variable "log_retention_days" {
  description = "CloudWatch log retention for the attestation Lambda."
  type        = number
  default     = 14
  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value CloudWatch Logs accepts (e.g. 1, 7, 14, 30, 90, 365)."
  }
}
