variable "region" {
  description = "AWS region for the example deployment."
  type        = string
  default     = "eu-west-1"
}

variable "notification_email" {
  description = "Email subscribed to the SNS topic. Override with your address to receive the confirmation + findings emails."
  type        = string
  default     = "alerts@example.com"
}

variable "enable_cost_allocation_tags" {
  description = "Activate the schema keys as cost-allocation tags. Needs the keys in billing data (~24h after first deploy, payer account); keep false on a first deploy."
  type        = bool
  default     = false
}
