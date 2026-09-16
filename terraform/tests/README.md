# Contract and compatibility tests

This directory contains non-mutating tests for the resource-free architecture contracts. The runner executes OpenTofu validation in disposable temporary directories and includes deliberate invalid cases. A passing positive case is not sufficient: every named negative case must fail for its intended contract reason.

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
