# golden-k8 — developer entry points. Run `make` or `make help` for the list.

SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help
MAKEFLAGS += --no-print-directory

# Use the tool versions pinned in mise.toml whenever mise is installed.
RUN := $(if $(shell command -v mise 2>/dev/null),mise exec --,)

# Parameter file for the environment being worked on.
ENV ?= environments/local.yaml

# provider existing: CONFIRM_EXISTING=yes lets golden-k8 change a cluster it
# did not create (bootstrap, smoke, down). Guardrails refuse it otherwise.
CONFIRM_EXISTING ?=
confirm := $(if $(filter yes true 1,$(CONFIRM_EXISTING)),--confirm-existing)

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
test-terraform: ## Terraform tests, mocked, no cloud/Docker (PROVIDER=aws: one provider + shared modules)
	$(RUN) scripts/test-terraform.sh $(PROVIDER)

.PHONY: test-app
test-app: ## Sample app unit tests (go test -race)
	cd app && $(RUN) go test -race -count=1 ./...

.PHONY: test-guardrails
test-guardrails: ## provider existing guardrails against fake kubeconfigs (no cluster)
	$(RUN) scripts/test-guardrails.sh

.PHONY: test-manifests
test-manifests: ## Build every app overlay and validate it with kubeconform
	$(RUN) scripts/test-manifests.sh

.PHONY: validate
validate: lint test-config test-terraform test-guardrails test-app test-manifests ## Full static validation

##@ Config

.PHONY: config
config: ## Merge defaults + ENV and validate into build/config.json
	$(RUN) scripts/config.sh $(ENV) build/config.json

##@ Environment lifecycle

.PHONY: infra-up
infra-up: config ## Create the cluster for ENV (local: kind; existing: kubeconfig snapshot only) → build/contract.json
	$(RUN) scripts/infra.sh up build/config.json

.PHONY: infra-down
infra-down: config ## Destroy the cluster for ENV (existing: only forgets the state; use make down)
	$(RUN) scripts/infra.sh down build/config.json

.PHONY: bootstrap
bootstrap: ## Install the platform and the app with Ansible (needs make infra-up and make image)
	$(RUN) scripts/playbook.sh bootstrap $(confirm)

.PHONY: check-observability
check-observability: ## Grafana via the Gateway, Prometheus targets up, memory budget (needs make bootstrap)
	$(RUN) scripts/observability.sh check

.PHONY: grafana
grafana: ## Print the Grafana URL and admin login for the running environment
	$(RUN) scripts/observability.sh login

.PHONY: image
image: ## Build the sample app image (< 20 MB) and load it into kind (never pushed)
	$(RUN) scripts/image.sh build/config.json $(confirm)

.PHONY: up
up: infra-up ## Full environment: config → infra → image → bootstrap (platform + app)
	$(MAKE) image bootstrap

.PHONY: smoke
smoke: ## Smoke tests: app via the Gateway, scraped by Prometheus, dashboard, HPA metrics
	$(RUN) scripts/playbook.sh smoke $(confirm)

.PHONY: down
down: config ## Tear down ENV: local destroys the kind cluster; existing removes only what golden-k8 installed
	$(RUN) scripts/down.sh build/config.json $(confirm)

.PHONY: render
render: config ## Render + schema-check everything ENV would apply, no cluster needed (any provider)
	$(RUN) scripts/render.sh build/config.json

##@ Housekeeping

.PHONY: clean
clean: ## Remove generated build output
	rm -rf build/

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make <target> [ENV=environments/<name>.yaml]\n"} \
		/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } \
		/^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
