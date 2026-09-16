# Candidate consumer compatibility

`candidate_copy.py` creates an isolated copy of a consumer and rewrites only public `root-modules-tf` Git module sources to an explicitly supplied candidate checkout. The original consumer is never edited.

This is the source-selection half of the compatibility gate. The isolated copy must then use the consumer's own stack Makefile for `validate` and `plan`, with an owner-approved isolated state/input snapshot. A successful source rewrite is not a plan result.

The synthetic test is non-mutating:

```text
make -C terraform/tests compatibility-check
```

The manual candidate-copy interface requires external paths:

```text
make -C terraform/tests candidate-copy \
  PROTECTED_CONSUMER_CHECKOUT=... \
  CANDIDATE_SOURCE_ROOT=... \
  COMPAT_OUTPUT_DIR=... \
  COMPAT_MANIFEST=... \
  MODULE_MAP=... \
  INIT_DIRS=environments/staging/us-east-1/data
```

`MODULE_MAP` is a JSON object mapping each evaluated stack's relative directory to its expected module-key/package-name pairs. For example: `{"environments/test": {"database": "aws-eks-aurora-cluster"}}`. Select this mapping from the caller configuration before initialization, including every intended public module call and its full nested module key; do not derive it from the installed candidate being verified. Different stacks may select different package subsets.

The selection receipt records source-file hashes, archive and extracted-tree hashes, and the expected mapping. Changed source or packages, missing modules, wrong packages, and partial fallback to baseline modules fail verification. Older receipts without these fields are not accepted; preserve them as historical evidence rather than relabeling them as the corrected candidate.

After each copied stack is initialized through its own Makefile, run `make -C terraform/tests installed-candidate-check` with the same paths and `INIT_DIRS`. The verifier reads `.terraform/modules/modules.json` and checks installed module metadata/content against the recorded immutable selection and expected per-stack mapping. Rewritten source references without this receipt are not candidate-installation evidence.

Do not point `COMPAT_OUTPUT_DIR` at the real consumer checkout. Do not run the resulting plan against a live backend. The protected-consumer plan gate compares baseline and candidate actions, exact managed addresses and keys, outputs, rendered configuration, and shared operator-script behavior.

Run `make -C terraform/tests legacy-tenant-check BASELINE_SOURCE_ROOT="$BASELINE_SOURCE_ROOT" CANDIDATE_SOURCE_ROOT="$CANDIDATE_SOURCE_ROOT"` to compare the actual Aurora input validations and tenant-role derivations without resources or cloud access. Both source roots must be independently selected snapshots. Optional `LEGACY_CASES` supplies additional private expected-input/output cases and must remain outside the repository. This check does not compare infrastructure plans. `make -C terraform/tests isolated-validate CONFIG_DIR="$CONFIG_DIR"` initializes and validates a prepared disposable configuration copy; never point it at a protected checkout. Validation alone does not establish plan equivalence.
