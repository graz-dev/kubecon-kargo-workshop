# Kargo workshop (Phase 1, local cluster + Akuity Platform). One entry point per concern; scripts live in scripts/.
# Variables given on the command line (e.g. `make up HTTP_PORT=8080`) override workshop.env and .env.

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help bootstrap tools doctor login up down platform-down reset urls status seed release catchup check freight audit prefetch lint

# stub <target> <planned phase>
define stub
	@echo "make $(1): not implemented yet (planned for phase $(2))." >&2; exit 1
endef

help: ## List the targets
	@awk 'BEGIN {FS = ":.*## "; printf "Usage: make <target> [VAR=value]\n\nTargets:\n"} \
		/^[a-zA-Z_-]+:.*## / {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@printf '\nSettings: workshop.env and versions.env.\n'

bootstrap: ## Prepare this machine before the workshop: download the tools, run the checks, write a report
	@scripts/bootstrap.sh

tools: ## Download the pinned CLIs (kind, kubectl, helm, kargo, akuity, crane) into ./.tools/bin
	@scripts/tools.sh install

doctor: ## Check this machine (Docker, memory, ports, DNS, internet, tools, images); changes nothing
	@scripts/doctor.sh

login: ## Log in to the Akuity Platform with the akuity CLI (browser, once) and check your organization
	@scripts/login.sh

up: ## Create the kind cluster with Traefik and DNS, then connect it to the Akuity Platform (idempotent). SELFTEST=1 adds a routing test, SKIP_PLATFORM=1 stops before the platform, DRY_RUN=1 only shows what it would create there
	@scripts/up.sh

down: ## Delete the kind cluster (the instances on the Akuity Platform stay: see platform-down)
	@scripts/down.sh

platform-down: ## Delete the Argo CD and Kargo instances this workshop created on the platform (a dry run unless CONFIRM=yes)
	@scripts/platform-down.sh

reset: ## Back to the start of the labs without rebuilding the cluster (a dry run unless CONFIRM=yes)
	@scripts/reset.sh

urls: ## Print the URLs of every UI
	@scripts/urls.sh

status: ## Show the state of the cluster
	@scripts/status.sh

seed: ## Install Gitea with the GitOps repo, then create the Argo CD apps and the Kargo project (idempotent). SKIP_PLATFORM=1 = Gitea only, DRY_RUN=1 = show the platform part
	@scripts/seed.sh

release: ## Make a new image version visible to the Warehouse: make release VERSION=1.1.0
	$(if $(VERSION),,$(error VERSION is required, e.g. make release VERSION=1.1.0))
	@scripts/release.sh $(VERSION)

catchup: ## Do a lab, and the ones before it, for you when you are behind: make catchup STEP=1
	$(if $(STEP),,$(error STEP is required, e.g. make catchup STEP=1))
	@scripts/catchup.sh $(STEP)

check: ## Verify a step: make check STEP=setup, or a lab number: make check STEP=1
	$(if $(STEP),,$(error STEP is required, e.g. make check STEP=setup))
	@scripts/check.sh $(STEP)

audit: ## List the audit events of the project: who approved what, and why
	@scripts/audit.sh

freight: ## List the Freight with its version and where it is now (to find the alias of a version)
	@scripts/freight.sh

prefetch: ## Pull every image the workshop needs, so a later make up needs little or no network
	@scripts/prefetch.sh

lint: ## Syntax-check the scripts (bash -n) and run shellcheck/yamllint when installed
	@scripts/lint.sh
