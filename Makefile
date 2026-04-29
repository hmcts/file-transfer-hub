.PHONY: check format lint validate terraform-check terraform-format terraform-lint terraform-validate

APP_DIR := app
TERRAFORM_DIRS := components environments
TERRAFORM_MODULE_DIRS := components/core components/container-app
TF_CONTAINER_NAME ?= tf
HOST_WORKSPACE_ROOT ?= $(HOME)/workspace
TF_CONTAINER_WORKSPACE_ROOT ?= /workspace
TF_CONTAINER_CWD := $(patsubst $(HOST_WORKSPACE_ROOT)%,$(TF_CONTAINER_WORKSPACE_ROOT)%,$(CURDIR))

check:
	@$(MAKE) format
	@$(MAKE) lint
	@$(MAKE) validate

format: terraform-format
	@$(MAKE) -C $(APP_DIR) format

lint: terraform-lint
	@$(MAKE) -C $(APP_DIR) lint

validate: terraform-validate
	@$(MAKE) -C $(APP_DIR) validate

terraform-check:
	@docker exec $(TF_CONTAINER_NAME) sh -lc 'test -d "$(TF_CONTAINER_CWD)"'

terraform-format: terraform-check
	@docker exec $(TF_CONTAINER_NAME) sh -lc 'cd "$(TF_CONTAINER_CWD)" && mise exec -- terraform fmt -recursive $(TERRAFORM_DIRS)'

terraform-lint: terraform-check
	@docker exec $(TF_CONTAINER_NAME) sh -lc 'cd "$(TF_CONTAINER_CWD)" && mise exec -- terraform fmt -check -diff -recursive $(TERRAFORM_DIRS)'

terraform-validate: terraform-check
	@for module_dir in $(TERRAFORM_MODULE_DIRS); do \
		docker exec $(TF_CONTAINER_NAME) sh -lc 'cd "$(TF_CONTAINER_CWD)" && mise exec -- terraform -chdir='"$$module_dir"' init -backend=false -input=false' >/dev/null; \
		docker exec $(TF_CONTAINER_NAME) sh -lc 'cd "$(TF_CONTAINER_CWD)" && mise exec -- terraform -chdir='"$$module_dir"' validate'; \
	done