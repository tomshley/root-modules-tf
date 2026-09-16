# Operator rendering compatibility

`renderer_cases.py` checks the shared operator bundle catalog and shell syntax without reading a stack, state, secure file, or credential. It proves the catalog guard rejects a deliberate bundle-name mutation.

Compare independently selected baseline and candidate toolboxes through the wrapper:

```text
make -C terraform/tests renderer-check BASELINE_TOOLBOX="$BASELINE_TOOLBOX" CANDIDATE_TOOLBOX="$CANDIDATE_TOOLBOX"
```

An identical toolbox tree establishes unchanged renderer code and dependencies. Changed renderer code requires representative output comparisons using synthetic or explicitly approved isolated inputs; never write into a protected consumer's secure-files destination.
