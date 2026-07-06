.DEFAULT_GOAL := help

.PHONY: help init fmt validate lint scan test docs check clean

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

init: ## Init terraform (no backend) and tflint plugins
	terraform init -backend=false
	tflint --init

fmt: ## Format all terraform files
	terraform fmt -recursive

validate: ## Validate terraform
	terraform init -backend=false >/dev/null && terraform validate

lint: ## Run tflint
	tflint

scan: ## Run checkov governance/security scan
	checkov -d . --quiet

test: ## Run terraform tests
	terraform test

docs: ## Generate inputs/outputs docs
	terraform-docs markdown table .

check: fmt validate lint scan test ## Run every safe check (no apply)

clean: ## Remove local terraform caches and build artifacts
	find . -type d -name '.terraform' -prune -exec rm -rf {} +
	find . -type d -name '__pycache__' -prune -exec rm -rf {} +
	find . -type f -name '*.zip' -delete

# apply / destroy are intentionally absent — run those manually, with creds,
# after reviewing the plan. Keeping them out of the Makefile is a guardrail.
