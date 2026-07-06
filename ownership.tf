# ownership.tf — the attestation engine's infrastructure.
# EventBridge Scheduler invokes the Lambda on a cron; it re-validates every
# owner-tagged resource against the registry and flags drift. Flag-only: tag +
# notify, never stop/delete.

locals {
  ownership_function_name = "${var.name_prefix}-ownership-attestation"
  ownership_runtime       = "python3.13"
}

# Package the Lambda at plan time. Output lands in build/ (gitignored).
data "archive_file" "ownership" {
  type        = "zip"
  source_file = "${path.module}/lambda/ownership_check.py"
  output_path = "${path.module}/build/ownership_check.zip"
}

# Pre-create the log group to set retention (Lambda's implicit one never expires).
resource "aws_cloudwatch_log_group" "ownership" {
  #checkov:skip=CKV_AWS_158:Synthetic, non-sensitive logs; CMK log encryption deferred (default encryption applies).
  #checkov:skip=CKV_AWS_338:Retention is configurable; defaulted short for a near-zero-cost demo.
  name              = "/aws/lambda/${local.ownership_function_name}"
  retention_in_days = var.log_retention_days
}

# --- Lambda execution role -------------------------------------------------

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ownership_lambda" {
  name               = "${var.name_prefix}-ownership-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "ownership_lambda" {
  #checkov:skip=CKV_AWS_356:Tagging API, governed service tagging, and X-Ray have no resource-level scoping; writes are constrained to the status key via aws:TagKeys.

  # Logs — scoped to this function's log group.
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.ownership.arn}:*"]
  }

  # Discover owner-tagged resources (account-wide API; requires "*").
  statement {
    sid       = "DiscoverTaggedResources"
    actions   = ["tag:GetResources"]
    resources = ["*"]
  }

  # Write only the ownership status tag (aws:TagKeys constrains it).
  statement {
    sid       = "WriteStatusTagOnly"
    actions   = ["tag:TagResources"]
    resources = ["*"]
    condition {
      test     = "ForAllValues:StringEquals"
      variable = "aws:TagKeys"
      values   = [local.status_tag_key]
    }
  }

  # Service tagging APIs that tag:TagResources delegates to (var.governed_tagging_actions).
  # WriteStatusTagOnly already constrains the written key to ownership:status.
  statement {
    sid       = "GovernedServiceTagging"
    actions   = var.governed_tagging_actions
    resources = ["*"]
  }

  # Publish findings to the encrypted topic, and use the CMK to encrypt them.
  statement {
    sid       = "PublishFindings"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.notifications.arn]
  }
  statement {
    sid       = "UseNotificationKey"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = [aws_kms_key.notifications.arn]
  }

  # X-Ray tracing (no resource-level scoping available for these actions).
  statement {
    sid       = "Tracing"
    actions   = ["xray:PutTraceSegments", "xray:PutTelemetryRecords"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "ownership_lambda" {
  name   = "${var.name_prefix}-ownership-lambda"
  role   = aws_iam_role.ownership_lambda.id
  policy = data.aws_iam_policy_document.ownership_lambda.json
}

# --- The Lambda ------------------------------------------------------------

resource "aws_lambda_function" "ownership" {
  #checkov:skip=CKV_AWS_117:No VPC resources to reach; the function only calls AWS APIs.
  #checkov:skip=CKV_AWS_116:Invoked by EventBridge Scheduler (target retry_policy handles failures); the async Lambda DLQ doesn't apply.
  #checkov:skip=CKV_AWS_173:Synthetic, non-sensitive env; default encryption applies. Customer CMK adds an apply-time grant, deferred.
  #checkov:skip=CKV_AWS_272:Code signing out of scope for a single-file demo Lambda.
  function_name = local.ownership_function_name
  role          = aws_iam_role.ownership_lambda.arn
  runtime       = local.ownership_runtime
  handler       = "ownership_check.handler"

  filename         = data.archive_file.ownership.output_path
  source_code_hash = data.archive_file.ownership.output_base64sha256

  timeout                        = 60
  memory_size                    = 128
  reserved_concurrent_executions = 1

  tracing_config {
    mode = "Active"
  }

  environment {
    variables = {
      OWNERS_REGISTRY       = jsonencode(local.owners_by_id)
      SNS_TOPIC_ARN         = aws_sns_topic.notifications.arn
      OWNER_TAG_KEY         = local.owner_tag_key
      STATUS_TAG_KEY        = local.status_tag_key
      RESOURCE_TYPE_FILTERS = jsonencode(var.tag_resource_types)
    }
  }

  depends_on = [aws_cloudwatch_log_group.ownership]
}

# --- EventBridge Scheduler ---

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
    # Confused-deputy protection: only our account's scheduler may assume this.
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  name               = "${var.name_prefix}-ownership-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    sid     = "InvokeOwnershipLambda"
    actions = ["lambda:InvokeFunction"]
    # ARN built from parts: referencing the function resource would defer this
    # data source (policy rendered "known after apply") on every function
    # update, e.g. each registry change.
    resources = ["arn:${data.aws_partition.current.partition}:lambda:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:function:${local.ownership_function_name}"]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name   = "${var.name_prefix}-ownership-scheduler"
  role   = aws_iam_role.scheduler.id
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}

resource "aws_scheduler_schedule" "ownership" {
  #checkov:skip=CKV_AWS_297:The schedule carries no sensitive payload; a customer CMK adds apply-time key-grant surface, deferred for the synthetic demo.
  name = local.ownership_function_name

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression = var.ownership_schedule

  target {
    arn      = aws_lambda_function.ownership.arn
    role_arn = aws_iam_role.scheduler.arn

    retry_policy {
      maximum_retry_attempts = 3
    }
  }
}
