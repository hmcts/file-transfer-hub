.PHONY: check check-code check-docs ci_verify fmt fmt-code fmt-docs lint validate test verify makefile-lint shell-fmt shell-fmt-check shell-lint shell-validate terraform-fmt terraform-lint terraform-validate

APP_DIR := app
CHECKMAKE_FILES := Makefile app/Makefile
TERRAFORM_DIRS := components environments
TERRAFORM_MODULE_DIRS := components/core components/container-app

# Root level targets

fmt: fmt-code fmt-docs

check: check-code check-docs

test:
	@$(MAKE) -C $(APP_DIR) test

verify: fmt check test
 
ci_verify: check test

fmt-code: terraform-fmt shell-fmt

fmt-docs:
	@rumdl fmt .

check-code:
	@$(MAKE) shell-fmt-check
	@$(MAKE) terraform-fmt-check
	@$(MAKE) lint
	@$(MAKE) validate

check-docs:
	@rumdl fmt --check --diff .
	@rumdl check .

# Component level targets

lint: makefile-lint shell-lint

validate: terraform-validate shell-validate

makefile-lint:
	@set -e; \
	for makefile in $(CHECKMAKE_FILES); do \
		checkmake "$$makefile"; \
	done

shell-fmt:
	@$(MAKE) -C $(APP_DIR) fmt

shell-fmt-check:
	@$(MAKE) -C $(APP_DIR) fmt-check

shell-lint:
	@$(MAKE) -C $(APP_DIR) lint

shell-validate:
	@$(MAKE) -C $(APP_DIR) validate

terraform-fmt:
	@terraform fmt -recursive $(TERRAFORM_DIRS)

terraform-fmt-check:
	@terraform fmt -check -diff -recursive $(TERRAFORM_DIRS)

terraform-validate:
	@for module_dir in $(TERRAFORM_MODULE_DIRS); do \
		terraform -chdir="$$module_dir" init -backend=false -input=false >/dev/null; \
		terraform -chdir="$$module_dir" validate; \
	done