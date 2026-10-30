# Contract and compatibility tests

This directory contains non-mutating tests for the resource-free architecture contracts. The runner executes OpenTofu validation in disposable temporary directories and includes deliberate invalid cases. A passing positive case is not sufficient: every named negative case must fail for its intended contract reason.

Cases for provider-backed modules plan with `-refresh=false` against empty state; for the Cloudflare cases the runner exports a placeholder `CLOUDFLARE_API_TOKEN` so the provider can configure itself, and no request ever reaches the Cloudflare API. Provider downloads are shared across cases through `TF_PLUGIN_CACHE_DIR`, with `TF_PLUGIN_CACHE_MAY_BREAK_DEPENDENCY_LOCK_FILE` set so the lock-file-less case directories actually read the cache; the environment's own values for either variable win. The same run validates each pause example root listed in `EXAMPLE_ROOTS` against the modules in this tree, sharing that cache, and checks that every move in `REQUIRED_MOVES` is still written in its module outside comments, for moves whose prior-state re-plan would need the module's whole state.

Run through the wrapper:

```text
make -C terraform/tests contract-check
make -C terraform/tests quality-check
make -C terraform/tests coverage-check
make -C terraform/tests compatibility-check
make -C terraform/tests renderer-check BASELINE_TOOLBOX="$BASELINE_TOOLBOX" CANDIDATE_TOOLBOX="$CANDIDATE_TOOLBOX"
make -C terraform/tests package-check
make -C terraform/tests report-check
```

These targets do not apply infrastructure, access a backend, read credentials, or provision a service. Protected-consumer candidate planning uses the separate isolated-copy interface and the consumer's own stack Makefile; runtime protocol behavior and recovery are outside this delivery. The renderer comparison requires independently selected baseline and candidate toolbox directories.
