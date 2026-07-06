# budgets.tf — AWS Budgets (actual + forecast) and Cost Anomaly Detection,
# both publishing to the SNS topic.

locals {
  # Threshold notifications: two on actual spend, one on forecast.
  budget_notifications = [
    { type = "ACTUAL", threshold = var.budget_thresholds.actual_warning },
    { type = "ACTUAL", threshold = var.budget_thresholds.actual_critical },
    { type = "FORECASTED", threshold = var.budget_thresholds.forecast_warning },
  ]
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.name_prefix}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_amount)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = local.budget_notifications
    content {
      comparison_operator       = "GREATER_THAN"
      threshold                 = notification.value.threshold
      threshold_type            = "PERCENTAGE"
      notification_type         = notification.value.type
      subscriber_sns_topic_arns = [aws_sns_topic.notifications.arn]
    }
  }
}

# CUSTOM monitor, not DIMENSIONAL: AWS allows one dimensional monitor per account
# and creates a default, so a second DIMENSIONAL fails; CUSTOM coexists.
resource "aws_ce_anomaly_monitor" "this" {
  count = var.enable_cost_anomaly_detection ? 1 : 0

  name         = "${var.name_prefix}-anomaly-monitor"
  monitor_type = "CUSTOM"
  # The API stores the spec with all unused members as explicit nulls; emit that
  # canonical form, or every plan sees a diff on this create-only attribute and
  # forces a replacement.
  monitor_specification = jsonencode({
    And            = null
    CostCategories = null
    Dimensions = {
      Key          = "LINKED_ACCOUNT"
      MatchOptions = null
      Values       = [data.aws_caller_identity.current.account_id]
    }
    Not  = null
    Or   = null
    Tags = null
  })
}

resource "aws_ce_anomaly_subscription" "this" {
  count = var.enable_cost_anomaly_detection ? 1 : 0

  name             = "${var.name_prefix}-anomaly-subscription"
  frequency        = "IMMEDIATE" # SNS delivery requires IMMEDIATE frequency
  monitor_arn_list = [aws_ce_anomaly_monitor.this[0].arn]

  subscriber {
    type    = "SNS"
    address = aws_sns_topic.notifications.arn
  }

  # Alert when an anomaly's absolute impact is at least this many USD.
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = [tostring(var.anomaly_impact_threshold)]
    }
  }
}
