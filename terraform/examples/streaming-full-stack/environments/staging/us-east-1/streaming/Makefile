TOFU ?= tofu
ENV_FILE ?= ../../../../.secure_files/.env
TF_ENV ?= $(notdir $(abspath $(CURDIR)/../..))
TF_REGION ?= $(notdir $(abspath $(CURDIR)/..))
TF_AREA ?= $(notdir $(CURDIR))
ENV_LOCAL_FILE ?= ../../../../.secure_files/$(TF_ENV)-$(TF_REGION)-$(TF_AREA).env
TFVARS_FILE ?= terraform.tfvars
SECURE_TFVARS_FILE ?=
PROJECT_KEY ?= myproject-infrastructure
TF_HOST ?= https://gitlab.com
TFVARS_ARGS = -var-file=$(TFVARS_FILE) $(if $(SECURE_TFVARS_FILE),-var-file=$(SECURE_TFVARS_FILE),)
TF_STATE_NAME = $(PROJECT_KEY)-$(TF_ENV)-$(TF_REGION)-$(TF_AREA)
BACKEND_ADDRESS ?= $(TF_HOST)/api/v4/projects/$(TF_PROJECT_ID)/terraform/state/$(TF_STATE_NAME)
BACKEND_ARGS = \
	-backend-config=address=$(BACKEND_ADDRESS) \
	-backend-config=lock_address=$(BACKEND_ADDRESS)/lock \
	-backend-config=unlock_address=$(BACKEND_ADDRESS)/lock \
	-backend-config=username=$(TF_USERNAME) \
	-backend-config=password=$(TF_PASSWORD) \
	-backend-config=lock_method=POST \
	-backend-config=unlock_method=DELETE \
	-backend-config=retry_wait_min=5

.PHONY: clean artifact init migrate reconfigure validate require-plan _planonly plan _applyonly apply planapply destroy

ifneq ("$(wildcard $(ENV_FILE))","")
include $(ENV_FILE)
export $(shell sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' $(ENV_FILE))
endif

ifneq ("$(wildcard $(ENV_LOCAL_FILE))","")
include $(ENV_LOCAL_FILE)
export $(shell sed -n 's/^\([A-Za-z_][A-Za-z0-9_]*\)=.*/\1/p' $(ENV_LOCAL_FILE))
endif

clean:
	rm -rf .terraform .tfstate.plan .tfstate.plan.txt .tfstate.plan.changes .tfstate.plan.json

artifact:
	$(TOFU) show -no-color .tfstate.plan > .tfstate.plan.txt
	$(TOFU) show -json .tfstate.plan | jq '[(.resource_changes // [])[] | select(.change.actions[0] != "no-op")] | length' > .tfstate.plan.changes
	$(TOFU) show -json .tfstate.plan | jq -r '([(.resource_changes // [])[].change.actions?] | flatten) | {"create":(map(select(.=="create")) | length),"update":(map(select(.=="update")) | length),"delete":(map(select(.=="delete")) | length)}' > .tfstate.plan.json

init:
	$(TOFU) init $(BACKEND_ARGS)

migrate:
	$(TOFU) init \
	-migrate-state \
	$(BACKEND_ARGS)

reconfigure:
	$(TOFU) init \
	-reconfigure \
	$(BACKEND_ARGS)

validate:
	$(TOFU) fmt -recursive -diff -check .
	$(TOFU) fmt -recursive -diff -check ../../../../stacks
	$(TOFU) init -backend=false
	$(TOFU) validate

require-plan:
	@test -f .tfstate.plan || (echo "Missing .tfstate.plan. Run 'make plan' first or use 'make planapply'." >&2; exit 1)

_planonly:
	$(TOFU) plan \
	-input=false \
	-lock=true \
	$(TFVARS_ARGS) \
	-out=.tfstate.plan

plan: clean init _planonly artifact

_applyonly:
	$(TOFU) apply \
	-input=false \
	-auto-approve \
	-lock=true \
	$(TFVARS_ARGS) \
	.tfstate.plan

apply: init require-plan _applyonly

planapply: clean init _planonly artifact
	$(MAKE) _applyonly

destroy: init
	$(TOFU) destroy \
	-input=false \
	-lock=true \
	$(TFVARS_ARGS)
