# Operator Scripts

This directory documents operator tool usage for this consumer infrastructure.

The actual scripts live in the shared `toolbox/operator-tools/` directory at the root of `root-modules-tf`. Consumer repos invoke them via workspace-local relative paths.

## Session Setup

```bash
# Resolve shared operator-tools relative to this example
TOOLS=../../../toolbox/operator-tools

# AWS session
source "$TOOLS/aws-session.sh" .secure_files/staging-us-east-1-cloud.env

# K8s discovery (requires AWS session)
source "$TOOLS/k8s-session.sh"

# Confluent session
source "$TOOLS/confluent-session.sh" .secure_files/staging-us-east-1-streaming.env
```

## Credential Bundle Rendering

After applying the streaming stack:

```bash
TOOLS=../../../toolbox/operator-tools
"$TOOLS/render-streaming-bundle.sh" environments/staging/us-east-1/streaming
```

This creates `.env-bundle/<workload>.env` files with Kafka and Schema Registry credentials.

## Thin Wrapper Pattern

Real consumer repos (e.g. `your-infra-repo`) typically add a thin wrapper script like `scripts/operator-session.sh` that chains all session tools for a given stack prefix:

```bash
source scripts/operator-session.sh staging-us-east-1
```

See `toolbox/operator-tools/README.md` for the full documentation and future expansion path.
