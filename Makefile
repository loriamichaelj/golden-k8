# golden-k8 — developer entry points. Run `make` or `make help` for the list.

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory

# Use the tool versions pinned in mise.toml whenever mise is installed.
RUN := $(if $(shell command -v mise 2>/dev/null),mise exec --,)

# Parameter file for the environment being worked on.
ENV ?= environments/local.yaml

# Placeholder for targets delivered by a later increment.
define todo
	@echo "make $@: not implemented yet ($(1))" >&2; exit 2
endef

##@ Setup

.PHONY: tools
tools: ## Install the pinned tool versions from mise.toml
	mise install

.PHONY: hooks
hooks: ## Install the pre-commit git hook
	$(RUN) pre-commit install --install-hooks

##@ Quality

.PHONY: lint
lint: ## Run every linter and scanner against the whole repo
	$(RUN) pre-commit run --all-files --show-diff-on-failure

.PHONY: secrets
secrets: ## Scan the full git history for secrets
	$(RUN) gitleaks git --redact --no-banner --verbose

.PHONY: test-config
test-config: ## Config contract tests (schema fixtures + example environments)
	$(RUN) scripts/test-config.sh

.PHONY: test-terraform
test-terraform: ## Terraform tests for every module and stack (mocked, no cloud/Docker)
	$(RUN) scripts/test-terraform.sh

.PHONY: validate
validate: lint test-config test-terraform ## Full static validation (grows with each increment)

##@ Config

.PHONY: config
config: ## Merge defaults + ENV and validate into build/config.json
	$(RUN) scripts/config.sh $(ENV) build/config.json

##@ Environment lifecycle

.PHONY: infra-up
infra-up: config ## Create the cluster for ENV (local: kind) → build/contract.json
	$(RUN) scripts/infra.sh up build/config.json

.PHONY: infra-down
infra-down: config ## Destroy the cluster for ENV
	$(RUN) scripts/infra.sh down build/config.json

.PHONY: bootstrap
bootstrap: ## Install the platform layer with Ansible (needs make infra-up)
	$(RUN) scripts/bootstrap.sh

.PHONY: image
image: ## Build the sample app image and load it into kind
	$(call todo,increment 5)

.PHONY: up
up: ## Full environment: config → infra → bootstrap → app
	$(call todo,increment 5)

.PHONY: smoke
smoke: ## Run smoke tests against the running environment
	$(call todo,increment 5)

.PHONY: down
down: ## Tear down everything golden-k8 created for ENV
	$(call todo,increment 5)

.PHONY: render
render: ## Render manifests for ENV without applying (any provider)
	$(call todo,increment 6)

##@ Housekeeping

.PHONY: clean
clean: ## Remove generated build output
	rm -rf build/

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target> [ENV=environments/<name>.yaml]\n"} \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
