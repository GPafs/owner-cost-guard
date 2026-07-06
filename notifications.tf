# notifications.tf — one KMS-encrypted SNS topic for all governance signals
# (ownership findings, Budgets, Cost Anomaly Detection).

# Customer-managed key: the AWS-managed alias/aws/sns key can't grant access to
# the Budgets / Cost Anomaly Detection service principals that publish here.
resource "aws_kms_key" "notifications" {
  description             = "Encrypts the ${var.name_prefix} notification topic"
  enable_key_rotation     = true
  deletion_window_in_days = 7
  policy                  = data.aws_iam_policy_document.notifications_kms.json
}

resource "aws_kms_alias" "notifications" {
  name          = "alias/${var.name_prefix}-notifications"
  target_key_id = aws_kms_key.notifications.key_id
}

data "aws_iam_policy_document" "notifications_kms" {
  # KMS key policy. The checks below are IAM-policy checks that misfire here
  # (resource "*" means this key; root admin is the anti-lockout baseline):
  #checkov:skip=CKV_AWS_109:KMS key policy — resource "*" is this key; root kms:* is the AWS anti-lockout baseline.
  #checkov:skip=CKV_AWS_111:KMS key policy — statements are scoped to this key, not unconstrained IAM write.
  #checkov:skip=CKV_AWS_356:KMS key policy — "*" resource in a key policy refers to this key only.

  # Account root admin: the anti-lockout baseline; lets IAM policies delegate key use.
  statement {
    sid       = "EnableAccountAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Publishing services need data-key access to encrypt messages to the topic.
  statement {
    sid       = "AllowCostServicesUseOfKey"
    effect    = "Allow"
    actions   = ["kms:GenerateDataKey*", "kms:Decrypt"]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com", "costalerts.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic" "notifications" {
  name              = "${var.name_prefix}-notifications"
  kms_master_key_id = aws_kms_key.notifications.id
}

resource "aws_sns_topic_policy" "notifications" {
  arn    = aws_sns_topic.notifications.arn
  policy = data.aws_iam_policy_document.notifications_topic.json
}

data "aws_iam_policy_document" "notifications_topic" {
  # Budgets and Cost Anomaly Detection publish here. (The Lambda role publishes
  # via its own IAM policy — same-account principals need no topic grant.)
  # Production hardening: scope publishers with aws:SourceAccount / aws:SourceArn.
  statement {
    sid       = "AllowCostServicesPublish"
    effect    = "Allow"
    actions   = ["SNS:Publish"]
    resources = [aws_sns_topic.notifications.arn]

    principals {
      type        = "Service"
      identifiers = ["budgets.amazonaws.com", "costalerts.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.notifications.arn
  protocol  = "email"
  endpoint  = var.notification_email
  # Email subscriptions require the recipient to confirm via the link AWS sends;
  # until then the subscription stays "pending confirmation".
}
