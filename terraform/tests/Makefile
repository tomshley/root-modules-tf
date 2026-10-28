# Copyright (c) 2017–present Tomshley LLC
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

SHELL := /bin/sh

ROOT := $(abspath $(CURDIR)/../..)
TOFU ?= tofu
PYTHON ?= python3
INIT_DIRS ?=
INIT_DIR_ARGS := $(foreach dir,$(INIT_DIRS),--init-dir $(dir))

.PHONY: help contract-check quality-check coverage-check adapter-check compatibility-check renderer-check renderer-negative-check candidate-copy installed-candidate-check package-build package-check report-check legacy-tenant-check isolated-validate

help:
	@printf '%s\n' 'contract-check     Validate typed contracts and deliberate negative cases' 'adapter-check      Check shared adapter wiring and future publication path' 'quality-check      Check formatting and public-source boundaries' 'coverage-check     Verify contract case discovery and execution' 'compatibility-check Test isolated candidate source resolution' 'renderer-check     Compare independent baseline/candidate operator toolboxes' 'renderer-negative-check Prove catalog mutation is rejected' 'candidate-copy     Rewrite protected consumer sources in an isolated copy' 'installed-candidate-check Verify installed modules after stack Makefile init' 'package-build      Build a dependency-closed module archive' 'package-check      Validate clean package installation and local closure' 'report-check       Validate the latest local receipt when present' 'legacy-tenant-check Compare released and candidate resource-free tenant behavior' 'isolated-validate   Initialize and validate an explicitly selected isolated configuration'

contract-check:
	$(PYTHON) "$(CURDIR)/contract_cases.py"

adapter-check:
	$(PYTHON) "$(CURDIR)/adapter_contract_check.py"

package-build:
	@test -n "$(MODULE)" || (echo 'MODULE is required' >&2; exit 2)
	@test -n "$(OUTPUT)" || (echo 'OUTPUT is required' >&2; exit 2)
	@test -n "$(MANIFEST)" || (echo 'MANIFEST is required' >&2; exit 2)
	$(PYTHON) "$(ROOT)/tools/module-package/package_module.py" --root "$(ROOT)" --module "$(MODULE)" --output "$(OUTPUT)" --manifest "$(MANIFEST)"

package-check:
	$(PYTHON) "$(CURDIR)/package_check.py"

quality-check:
	$(TOFU) fmt -recursive -check "$(ROOT)/terraform/modules"
	$(PYTHON) "$(CURDIR)/quality_check.py"

coverage-check:
	$(PYTHON) "$(CURDIR)/coverage_check.py"

compatibility-check:
	$(PYTHON) "$(CURDIR)/compatibility/compatibility_cases.py"

renderer-check:
	@test -n "$(BASELINE_TOOLBOX)" || (echo 'BASELINE_TOOLBOX is required' >&2; exit 2)
	@test -n "$(CANDIDATE_TOOLBOX)" || (echo 'CANDIDATE_TOOLBOX is required' >&2; exit 2)
	$(PYTHON) "$(CURDIR)/compatibility/renderer_compare.py" --baseline "$(BASELINE_TOOLBOX)" --candidate "$(CANDIDATE_TOOLBOX)"

renderer-negative-check:
	$(PYTHON) "$(CURDIR)/compatibility/renderer_cases.py"

candidate-copy:
	@test -n "$(PROTECTED_CONSUMER_CHECKOUT)" || (echo 'PROTECTED_CONSUMER_CHECKOUT is required' >&2; exit 2)
	@test -n "$(CANDIDATE_SOURCE_ROOT)" || (echo 'CANDIDATE_SOURCE_ROOT is required' >&2; exit 2)
	@test -n "$(COMPAT_OUTPUT_DIR)" || (echo 'COMPAT_OUTPUT_DIR is required' >&2; exit 2)
	@test -n "$(COMPAT_MANIFEST)" || (echo 'COMPAT_MANIFEST is required' >&2; exit 2)
	@test -n "$(MODULE_MAP)" || (echo 'MODULE_MAP is required' >&2; exit 2)
	$(PYTHON) "$(CURDIR)/compatibility/candidate_copy.py" --consumer "$(PROTECTED_CONSUMER_CHECKOUT)" --candidate "$(CANDIDATE_SOURCE_ROOT)" --output "$(COMPAT_OUTPUT_DIR)" --manifest "$(COMPAT_MANIFEST)" --module-map "$(MODULE_MAP)" $(INIT_DIR_ARGS)

installed-candidate-check:
	@test -n "$(PROTECTED_CONSUMER_CHECKOUT)" || (echo 'PROTECTED_CONSUMER_CHECKOUT is required' >&2; exit 2)
	@test -n "$(CANDIDATE_SOURCE_ROOT)" || (echo 'CANDIDATE_SOURCE_ROOT is required' >&2; exit 2)
	@test -n "$(COMPAT_OUTPUT_DIR)" || (echo 'COMPAT_OUTPUT_DIR is required' >&2; exit 2)
	@test -n "$(COMPAT_MANIFEST)" || (echo 'COMPAT_MANIFEST is required' >&2; exit 2)
	$(PYTHON) "$(CURDIR)/compatibility/installed_candidate_check.py" --consumer "$(COMPAT_OUTPUT_DIR)" --candidate "$(CANDIDATE_SOURCE_ROOT)" --manifest "$(COMPAT_MANIFEST)" $(INIT_DIR_ARGS)

report-check:
	$(PYTHON) "$(CURDIR)/report_check.py"

legacy-tenant-check:
	@test -n "$(BASELINE_SOURCE_ROOT)" || (echo 'BASELINE_SOURCE_ROOT is required' >&2; exit 2)
	@test -n "$(CANDIDATE_SOURCE_ROOT)" || (echo 'CANDIDATE_SOURCE_ROOT is required' >&2; exit 2)
	$(PYTHON) "$(CURDIR)/compatibility/legacy_tenancy_cases.py" --baseline "$(BASELINE_SOURCE_ROOT)" --candidate "$(CANDIDATE_SOURCE_ROOT)" $(if $(LEGACY_CASES),--cases "$(LEGACY_CASES)",)

isolated-validate:
	@test -n "$(CONFIG_DIR)" || (echo 'CONFIG_DIR is required' >&2; exit 2)
	@test -d "$(CONFIG_DIR)" || (echo 'CONFIG_DIR must exist' >&2; exit 2)
	$(TOFU) -chdir="$(CONFIG_DIR)" init -backend=false -input=false -no-color
	$(TOFU) -chdir="$(CONFIG_DIR)" validate -no-color
