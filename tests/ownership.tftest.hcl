# tests/ownership.tftest.hcl — the plan-time gate, proven.
#
# Asserts that `terraform plan` FAILS on a bad ownership badge and PASSES a good
# one. mock_provider "aws" returns fake values for AWS, so this runs with zero
# credentials (CI-friendly); the tag contract is pure Terraform and fails before
# any provider call anyway.

mock_provider "aws" {
  # aws_iam_policy_document.json must be valid JSON, or the roles/policies that
  # consume it reject the mocked value. Give every such data source a valid stub.
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

# Required inputs that aren't what we're testing — held constant across runs.
variables {
  notification_email    = "alerts@example.com"
  monthly_budget_amount = 100
}

# An owner that isn't in owners.yaml must be rejected at plan time.
run "rejects_unknown_owner" {
  command = plan

  variables {
    tags = {
      owner       = "ghost@example.com"
      cost-center = "cc-9"
      environment = "dev"
    }
  }

  expect_failures = [var.tags]
}

# A missing required key (no cost-center) must be rejected.
run "rejects_missing_required_key" {
  command = plan

  variables {
    tags = {
      owner       = "alice@example.com"
      environment = "dev"
    }
  }

  expect_failures = [var.tags]
}

# An environment outside dev|staging|prod must be rejected.
run "rejects_invalid_environment" {
  command = plan

  variables {
    tags = {
      owner       = "alice@example.com"
      cost-center = "cc-1001"
      environment = "qa"
    }
  }

  expect_failures = [var.tags]
}

# A valid badge (Alice, current) must pass and surface via validated_tags.
run "accepts_valid_tags" {
  command = plan

  variables {
    tags = {
      owner       = "alice@example.com"
      cost-center = "cc-1001"
      environment = "dev"
    }
  }

  assert {
    condition     = output.validated_tags["owner"] == "alice@example.com"
    error_message = "validated_tags should echo the validated owner"
  }
}
