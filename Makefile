ENV ?= dev

.PHONY: help fmt validate lint test plan apply platform ansible audit

help: ## Show targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*## "}{printf "  \033[36m%-10s\033[0m %s\n",$$1,$$2}'

fmt: ## Format Terraform and Terragrunt files
	terraform fmt -recursive terraform/
	terragrunt hclfmt --terragrunt-working-dir live/

validate: ## terraform validate every module
	@for m in terraform/modules/*/; do \
	  echo "--- $$m"; terraform -chdir=$$m init -backend=false -input=false >/dev/null && terraform -chdir=$$m validate || exit 1; \
	done

lint: ## yamllint, ansible-lint, tflint, promtool
	yamllint -c .yamllint.yml .
	cd ansible && ansible-lint playbooks/site.yml
	tflint --recursive --chdir terraform/modules
	promtool check rules observability/platform-alerts/rules/*.yaml

test: ## Unit tests: alert rules and FinOps script
	cd observability/platform-alerts/tests && promtool test rules *_test.yaml
	cd finops && python3 -m pytest -q

plan: ## terragrunt plan for ENV
	cd live/$(ENV) && terragrunt run-all plan

apply: ## terragrunt apply for ENV
	cd live/$(ENV) && terragrunt run-all apply

platform: ## Install platform services into the current kube-context
	cd kubernetes/platform && helmfile -e $(ENV) apply
	kubectl apply -f kubernetes/rbac/

ansible: ## Configure VMs of ENV
	cd ansible && ansible-playbook -i inventories/$(ENV) playbooks/site.yml

audit: ## Right-sizing report (needs PROM_URL)
	python3 finops/resource_audit.py --namespaces 'shop' --window 7d
