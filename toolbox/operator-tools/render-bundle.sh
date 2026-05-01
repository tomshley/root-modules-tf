#!/usr/bin/env bash
# render-bundle.sh — Render a single credential bundle from root-modules-tf
# stack outputs.
#
# Discoverable, on-brand with the modules in this repo: every bundle maps
# 1:1 to a root-modules-tf module's outputs. The customer says which
# bundle they want and where their stack outputs live; this script reads
# the outputs and writes a chmod-600 .env (or .pem) file at a path the
# customer chooses.
#
# Usage:
#   render-bundle.sh <bundle> [flags...]
#   render-bundle.sh --list
#   render-bundle.sh <bundle> --help
#
# Bundles (each anchored to a root-modules-tf module — see --list):
#   ci-deploy        Cloud + CI OIDC: cluster name, region, deploy role
#   aurora-config    Aurora connection: host, port, database
#   aurora-master    Aurora master credentials from Secrets Manager
#   aurora-tenant    Aurora tenant credentials from Secrets Manager
#   redis-config     ElastiCache Redis connection metadata (host/port/tls)
#   redis-auth       ElastiCache Redis AUTH credentials from Secrets Manager
#   keycloak         Keycloak cluster-internal URLs
#   s3-config        S3 bucket name + region
#   kafka-workload   Confluent Cloud workload credentials
#   rds-ca-pair      Amazon RDS CA bundle PEM + pointer .env
#   aws-arns         Project N TF outputs from N stacks into a single .env
#   registry         GitLab container registry credentials from .credentials.gitlab
#
# Each bundle is repo-agnostic: TF output names are passed as flags (with
# sensible defaults that match the root-modules-tf module's published
# output names), so consumers with renamed outputs override per-bundle.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/render-helpers.sh"

# --- Bundle catalog ---
# Used by --list and --help dispatch. Each line: bundle:module-anchor:short-description
BUNDLE_CATALOG=(
  "ci-deploy:aws-eks-cluster + aws-eks-ci-oidc-access:CI deploy bundle (cluster, region, OIDC role, namespace)"
  "aurora-config:aws-eks-aurora-cluster:Aurora connection config (host, port, database)"
  "aurora-master:aws-eks-aurora-cluster:Aurora credentials from cluster master secret"
  "aurora-tenant:aws-eks-aurora-cluster:Aurora credentials from a tenant secret (multi-tenant)"
  "redis-config:aws-eks-elasticache-redis:Redis connection metadata (host/port/tls; non-secret)"
  "redis-auth:aws-eks-elasticache-redis:Redis AUTH credentials from the AUTH-token Secrets Manager secret"
  "keycloak:aws-eks-keycloak:Keycloak cluster-internal URLs (JWKS, issuer, token)"
  "s3-config:aws-eks-secure-s3:S3 bucket name + region"
  "kafka-workload:confluent-streaming-workload-access:Per-workload Kafka + Schema Registry credentials"
  "rds-ca-pair:Amazon RDS:CA bundle PEM + pointer .env file"
  "aws-arns:(generic):Project N TF outputs from N stacks into a single .env"
  "registry:(Tomshley CI convention):GitLab container registry credentials from .credentials.gitlab"
)

# Parse "key=stack:output[map_key]" specs used by aws-arns
# Echoes "stack output map_key" to stdout (map_key empty if not a map lookup)
_parse_emit_spec() {
  local spec="$1"
  # spec format: KEY=STACK:OUTPUT or KEY=STACK:OUTPUT[MAP_KEY]
  local rhs="${spec#*=}"
  local stack="${rhs%%:*}"
  local rest="${rhs#*:}"
  local output map_key=""
  if [[ "$rest" == *"["*"]" ]]; then
    output="${rest%%\[*}"
    map_key="${rest#*\[}"
    map_key="${map_key%\]}"
  else
    output="$rest"
  fi
  echo "$stack" "$output" "$map_key"
}

# Read a TF output (scalar or map[key]) given a "stack:output[map_key]" spec,
# resolving the stack name to its directory via the parallel STACK_NAMES /
# STACK_DIRS_INDEXED arrays (bash 3.2-compatible — no associative arrays).
_lookup_stack_dir() {
  local name="$1"
  local i
  for i in "${!STACK_NAMES[@]}"; do
    if [[ "${STACK_NAMES[$i]}" == "$name" ]]; then
      echo "${STACK_DIRS_INDEXED[$i]}"; return 0
    fi
  done
  return 1
}

_lookup_fallback_spec() {
  local key="$1"
  local i
  for i in "${!FALLBACK_KEYS[@]}"; do
    if [[ "${FALLBACK_KEYS[$i]}" == "$key" ]]; then
      echo "${FALLBACK_SPECS[$i]}"; return 0
    fi
  done
  return 1
}

_read_spec() {
  local stack="$1" output="$2" map_key="$3"
  local dir
  dir=$(_lookup_stack_dir "$stack") || {
    echo "Error: --stack $stack=DIR was not provided" >&2
    return 1
  }
  if [[ -n "$map_key" ]]; then
    read_tf_output_map_value "$dir" "$output" "$map_key"
  else
    read_tf_output "$dir" "$output"
  fi
}

# ========================================================================
# Bundle: ci-deploy
# ========================================================================

_help_ci_deploy() {
  cat <<'EOF'
ci-deploy — CI deploy credential bundle.
Anchored to: aws-eks-cluster (cluster_name) + aws-eks-ci-oidc-access (ci_deploy_role_arn).

Usage:
  render-bundle.sh ci-deploy --out FILE --cloud-dir DIR --region REGION --namespace NS
                            [--cluster-output KEY] [--role-output KEY]

Required flags:
  --out FILE          Output .env file path
  --cloud-dir DIR     Cloud stack directory
  --region REGION     AWS region (e.g. us-east-1)
  --namespace NS      Kubernetes namespace the consumer deploys into

Optional flags:
  --cluster-output KEY   TF output key for cluster name (default: cluster_name)
  --role-output KEY      TF output key for CI deploy role (default: ci_deploy_role_arn)

Output file format:
  AWS_DEFAULT_REGION, AWS_REGION, K8S_CLUSTER_NAME, CI_DEPLOY_ROLE_ARN, K8S_NAMESPACE
EOF
}

_run_ci_deploy() {
  local out="" cloud_dir="" region="" ns="" cluster_key="cluster_name" role_key="ci_deploy_role_arn"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)            out="$2";          shift 2 ;;
      --cloud-dir)      cloud_dir="$2";    shift 2 ;;
      --region)         region="$2";       shift 2 ;;
      --namespace)      ns="$2";           shift 2 ;;
      --cluster-output) cluster_key="$2";  shift 2 ;;
      --role-output)    role_key="$2";     shift 2 ;;
      --help)           _help_ci_deploy; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$out" ]]       && { echo "ci-deploy: --out is required" >&2; exit 1; }
  [[ -z "$cloud_dir" ]] && { echo "ci-deploy: --cloud-dir is required" >&2; exit 1; }
  [[ -z "$region" ]]    && { echo "ci-deploy: --region is required" >&2; exit 1; }
  [[ -z "$ns" ]]        && { echo "ci-deploy: --namespace is required" >&2; exit 1; }

  local cluster ci_role
  cluster=$(read_tf_output_required "$cloud_dir" "$cluster_key" "cloud")
  ci_role=$(read_tf_output_required "$cloud_dir" "$role_key" "cloud")

  write_file_secure "$out" 600 <<EOF
# CI deploy credentials — rendered from cloud stack outputs
AWS_DEFAULT_REGION=$region
AWS_REGION=$region
K8S_CLUSTER_NAME=$cluster
CI_DEPLOY_ROLE_ARN=$ci_role
K8S_NAMESPACE=$ns
EOF
  emit_ok "$out"
}

# ========================================================================
# Bundle: aurora-config
# ========================================================================

_help_aurora_config() {
  cat <<'EOF'
aurora-config — Aurora connection config (host, port, database).
Anchored to: aws-eks-aurora-cluster.

Usage:
  render-bundle.sh aurora-config --out FILE --data-dir DIR
                                [--host-output KEY] [--port-output KEY]
                                [--database-output KEY[MAP_KEY]] [--ssl-require]

Required flags:
  --out FILE          Output .env file path
  --data-dir DIR      Data stack directory

Optional flags:
  --host-output KEY        TF output for cluster endpoint (default: aurora_cluster_endpoint)
  --port-output KEY        TF output for port (default: aurora_port; defaults to 5432 if missing)
  --database-output KEY    TF output for database name. May be a map(string) lookup
                           via KEY[MAP_KEY] syntax (e.g. tenant_database_names[my-tenant]).
                           If unset, the "database=" line is omitted.
  --ssl-require            Append "ssl=require" to the output.

Output file format (lines optional based on flags):
  host=..., port=..., database=..., [ssl=require]
EOF
}

_run_aurora_config() {
  local out="" data_dir="" host_key="aurora_cluster_endpoint" port_key="aurora_port"
  local db_key="" ssl_require="false"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)              out="$2";        shift 2 ;;
      --data-dir)         data_dir="$2";   shift 2 ;;
      --host-output)      host_key="$2";   shift 2 ;;
      --port-output)      port_key="$2";   shift 2 ;;
      --database-output)  db_key="$2";     shift 2 ;;
      --ssl-require)      ssl_require="true"; shift ;;
      --help)             _help_aurora_config; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$out" ]]      && { echo "aurora-config: --out is required" >&2; exit 1; }
  [[ -z "$data_dir" ]] && { echo "aurora-config: --data-dir is required" >&2; exit 1; }

  local host port db_name=""
  host=$(read_tf_output_required "$data_dir" "$host_key" "data")
  port=$(read_tf_output "$data_dir" "$port_key")
  port="${port:-5432}"

  if [[ -n "$db_key" ]]; then
    if [[ "$db_key" == *"["*"]" ]]; then
      local key="${db_key%%\[*}"
      local map_key="${db_key#*\[}"; map_key="${map_key%\]}"
      db_name=$(read_tf_output_map_value "$data_dir" "$key" "$map_key")
      if [[ -z "$db_name" ]]; then
        echo "aurora-config: $key[$map_key] is empty in data stack" >&2
        exit 1
      fi
    else
      db_name=$(read_tf_output "$data_dir" "$db_key")
    fi
  fi

  # The trailing [[ ]] && echo pattern would return 1 when the condition is
  # false; under set -o pipefail that propagates as the pipeline exit and
  # set -e silently kills the script. Wrap in if/then/fi so the group always
  # returns 0 when no optional line is emitted.
  {
    echo "host=$host"
    echo "port=$port"
    if [[ -n "$db_name" ]]; then echo "database=$db_name"; fi
    if [[ "$ssl_require" == "true" ]]; then echo "ssl=require"; fi
  } | write_file_secure "$out" 600
  emit_ok "$out"
}

# ========================================================================
# Bundle: aurora-master
# ========================================================================

_help_aurora_master() {
  cat <<'EOF'
aurora-master — Aurora credentials from the cluster master secret.
Anchored to: aws-eks-aurora-cluster (master_secret_arn).

Usage:
  render-bundle.sh aurora-master --out FILE --region REGION
                                (--secret-arn ARN | --secret-arn-output KEY --data-dir DIR)
                                [--default-username USER]

Required flags:
  --out FILE              Output .env file path
  --region REGION         AWS region for Secrets Manager
  --secret-arn ARN        Direct Secrets Manager ARN, OR
  --secret-arn-output KEY TF output key for the ARN (in --data-dir)
  --data-dir DIR          Data stack directory (required if --secret-arn-output is used)

Optional flags:
  --default-username USER Default if .username is missing in the secret JSON (default: postgres)

Output file format:
  username=..., password=...

Skip behaviour: if the secret cannot be read or the password is empty, emits
a skip and writes nothing.
EOF
}

_run_aurora_master() {
  local out="" region="" secret_arn="" secret_arn_key="" data_dir=""
  local default_user="postgres"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)                out="$2";            shift 2 ;;
      --region)             region="$2";         shift 2 ;;
      --secret-arn)         secret_arn="$2";     shift 2 ;;
      --secret-arn-output)  secret_arn_key="$2"; shift 2 ;;
      --data-dir)           data_dir="$2";       shift 2 ;;
      --default-username)   default_user="$2";   shift 2 ;;
      --help)               _help_aurora_master; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$out" ]]    && { echo "aurora-master: --out is required" >&2; exit 1; }
  [[ -z "$region" ]] && { echo "aurora-master: --region is required" >&2; exit 1; }

  if [[ -z "$secret_arn" ]]; then
    [[ -z "$secret_arn_key" ]] && { echo "aurora-master: provide --secret-arn or --secret-arn-output" >&2; exit 1; }
    [[ -z "$data_dir" ]] && { echo "aurora-master: --data-dir is required when using --secret-arn-output" >&2; exit 1; }
    secret_arn=$(read_tf_output "$data_dir" "$secret_arn_key")
  fi

  if [[ -z "$secret_arn" ]]; then
    emit_skip "$(basename "$out") (master secret ARN not in stack outputs)"
    return
  fi

  local secret_json db_user db_pass
  secret_json=$(get_secret_string "$secret_arn" "$region")
  if [[ -z "$secret_json" ]]; then
    emit_skip "$(basename "$out") (could not read Secrets Manager: $secret_arn)"
    return
  fi
  db_user=$(echo "$secret_json" | jq -r --arg d "$default_user" '.username // $d')
  db_pass=$(echo "$secret_json" | jq -r '.password // empty')
  if [[ -z "$db_pass" ]]; then
    emit_skip "$(basename "$out") (password empty in Secrets Manager)"
    return
  fi

  write_file_secure "$out" 600 <<EOF
username=$db_user
password=$db_pass
EOF
  emit_ok "$out"
}

# ========================================================================
# Bundle: aurora-tenant
# ========================================================================

_help_aurora_tenant() {
  cat <<'EOF'
aurora-tenant — Aurora credentials from a per-tenant secret.
Anchored to: aws-eks-aurora-cluster (tenant_secret_arns map output).

Usage:
  render-bundle.sh aurora-tenant --out FILE --region REGION
                                (--secret-arn ARN | --secret-arn-output KEY[MAP_KEY] --data-dir DIR)

Required flags (same as aurora-master, but supports map[key] in --secret-arn-output)
Optional flags: (none)

Skip behaviour: emits a more diagnostic skip than aurora-master, since the
common cause of an unpopulated tenant secret is "the migrate Job has not
yet run" rather than IAM/network.
EOF
}

_run_aurora_tenant() {
  local out="" region="" secret_arn="" secret_arn_spec="" data_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)                out="$2";              shift 2 ;;
      --region)             region="$2";           shift 2 ;;
      --secret-arn)         secret_arn="$2";       shift 2 ;;
      --secret-arn-output)  secret_arn_spec="$2";  shift 2 ;;
      --data-dir)           data_dir="$2";         shift 2 ;;
      --help)               _help_aurora_tenant; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$out" ]]    && { echo "aurora-tenant: --out is required" >&2; exit 1; }
  [[ -z "$region" ]] && { echo "aurora-tenant: --region is required" >&2; exit 1; }

  if [[ -z "$secret_arn" ]]; then
    [[ -z "$secret_arn_spec" ]] && { echo "aurora-tenant: provide --secret-arn or --secret-arn-output" >&2; exit 1; }
    [[ -z "$data_dir" ]] && { echo "aurora-tenant: --data-dir is required when using --secret-arn-output" >&2; exit 1; }
    if [[ "$secret_arn_spec" == *"["*"]" ]]; then
      local key="${secret_arn_spec%%\[*}"
      local map_key="${secret_arn_spec#*\[}"; map_key="${map_key%\]}"
      secret_arn=$(read_tf_output_map_value "$data_dir" "$key" "$map_key")
    else
      secret_arn=$(read_tf_output "$data_dir" "$secret_arn_spec")
    fi
  fi

  if [[ -z "$secret_arn" ]]; then
    echo "aurora-tenant: tenant secret ARN is empty in data stack outputs" >&2
    exit 1
  fi

  local secret_json db_user db_pass
  secret_json=$(get_secret_string "$secret_arn" "$region")
  if [[ -z "$secret_json" ]]; then
    emit_skip "$(basename "$out") (most likely the tenant migrate Job has not yet run and the tenant secret has no version; less likely: missing IAM permission on $secret_arn, secret deleted, network failure, or KMS Decrypt denied)"
    return
  fi
  db_user=$(echo "$secret_json" | jq -r '.username // empty')
  db_pass=$(echo "$secret_json" | jq -r '.password // empty')
  if [[ -z "$db_user" || -z "$db_pass" ]]; then
    emit_skip "$(basename "$out") (tenant secret has a version but is missing username/password — migrate Job partially populated the secret; inspect $secret_arn and re-run migrate)"
    return
  fi

  write_file_secure "$out" 600 <<EOF
username=$db_user
password=$db_pass
EOF
  emit_ok "$out"
}

# ========================================================================
# Bundle: redis-config
# ========================================================================

_help_redis_config() {
  cat <<'EOF'
redis-config — Redis connection metadata (host/port/tls; non-secret).
Anchored to: aws-eks-elasticache-redis.

Usage:
  render-bundle.sh redis-config --out FILE --data-dir DIR
                               [--host-output KEY] [--port-output KEY] [--tls true|false]

Required flags:
  --out FILE         Output .env file path
  --data-dir DIR     Data stack directory

Optional flags:
  --host-output KEY  TF output for primary endpoint (default: redis_primary_endpoint)
  --port-output KEY  TF output for port (default: redis_port; defaults to 6379 if missing)
  --tls true|false   Whether to emit "tls=true|false" line (default: true)

Output file format:
  host=..., port=..., tls=...

Note: AUTH token is NOT written here. Use the redis-auth bundle (parallel
to aurora-tenant) to render the AUTH password into a sibling file when the
consumer needs deploy-time file-based credential injection. For runtime
ESO / Secrets Manager CSI patterns, surface the secret ARN via aws-arns
instead.
EOF
}

_run_redis_config() {
  local out="" data_dir="" host_key="redis_primary_endpoint" port_key="redis_port" tls="true"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)         out="$2";       shift 2 ;;
      --data-dir)    data_dir="$2";  shift 2 ;;
      --host-output) host_key="$2";  shift 2 ;;
      --port-output) port_key="$2";  shift 2 ;;
      --tls)         tls="$2";       shift 2 ;;
      --help)        _help_redis_config; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$out" ]]      && { echo "redis-config: --out is required" >&2; exit 1; }
  [[ -z "$data_dir" ]] && { echo "redis-config: --data-dir is required" >&2; exit 1; }

  local host port
  host=$(read_tf_output_required "$data_dir" "$host_key" "data")
  port=$(read_tf_output "$data_dir" "$port_key")
  port="${port:-6379}"

  write_file_secure "$out" 600 <<EOF
host=$host
port=$port
tls=$tls
EOF
  emit_ok "$out"
}

# ========================================================================
# Bundle: redis-auth
# ========================================================================

_help_redis_auth() {
  cat <<'EOF'
redis-auth — Redis AUTH credentials from the AUTH-token Secrets Manager secret.
Anchored to: aws-eks-elasticache-redis (auth_token_secret_arn).

Usage:
  render-bundle.sh redis-auth --out FILE --region REGION
                             (--secret-arn ARN | --secret-arn-output KEY --data-dir DIR)

Required flags:
  --out FILE              Output .env file path
  --region REGION         AWS region
  Either --secret-arn ARN OR --secret-arn-output KEY --data-dir DIR

Output file format:
  password=<auth-token>

The aws-eks-elasticache-redis module emits a JSON secret with shape
{ host, port, password }. Only `password` is written here so the file
can be consumed via `kubectl create secret generic --from-env-file=...`
without polluting the Secret with non-credential keys (host/port belong
in the redis-config ConfigMap).

Skip behaviour: if the secret cannot be read or the password field is
empty, this bundle skips with a diagnostic rather than writing an empty
file. Mirrors aurora-tenant's failure handling — keeps consumer CI from
silently propagating empty credentials.
EOF
}

_run_redis_auth() {
  local out="" region="" secret_arn="" secret_arn_key="" data_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)               out="$2";            shift 2 ;;
      --region)            region="$2";         shift 2 ;;
      --secret-arn)        secret_arn="$2";     shift 2 ;;
      --secret-arn-output) secret_arn_key="$2"; shift 2 ;;
      --data-dir)          data_dir="$2";       shift 2 ;;
      --help)              _help_redis_auth; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$out" ]]    && { echo "redis-auth: --out is required" >&2; exit 1; }
  [[ -z "$region" ]] && { echo "redis-auth: --region is required" >&2; exit 1; }

  if [[ -z "$secret_arn" ]]; then
    [[ -z "$secret_arn_key" ]] && { echo "redis-auth: provide --secret-arn or --secret-arn-output" >&2; exit 1; }
    [[ -z "$data_dir" ]] && { echo "redis-auth: --data-dir is required when using --secret-arn-output" >&2; exit 1; }
    secret_arn=$(read_tf_output "$data_dir" "$secret_arn_key")
  fi

  if [[ -z "$secret_arn" ]]; then
    emit_skip "$(basename "$out") (redis AUTH secret ARN not in stack outputs — Redis cluster likely not provisioned for this env)"
    return
  fi

  local secret_json redis_pass
  secret_json=$(get_secret_string "$secret_arn" "$region")
  if [[ -z "$secret_json" ]]; then
    emit_skip "$(basename "$out") (could not read Secrets Manager: $secret_arn — likely IAM permission denied, KMS Decrypt denied, or network failure)"
    return
  fi
  redis_pass=$(echo "$secret_json" | jq -r '.password // empty')
  if [[ -z "$redis_pass" ]]; then
    emit_skip "$(basename "$out") (redis AUTH secret has a version but is missing the password field)"
    return
  fi

  write_file_secure "$out" 600 <<EOF
password=$redis_pass
EOF
  emit_ok "$out"
}

# ========================================================================
# Bundle: keycloak
# ========================================================================

_help_keycloak() {
  cat <<'EOF'
keycloak — Keycloak cluster-internal URLs (JWKS, issuer, token).
Anchored to: aws-eks-keycloak.

Usage:
  render-bundle.sh keycloak --out FILE --identity-dir DIR --realm REALM
                           [--namespace-output KEY] [--service-output KEY] [--port-output KEY]

Required flags:
  --out FILE             Output .env file path
  --identity-dir DIR     Identity stack directory
  --realm REALM          Keycloak realm name (path segment in URLs)

Optional flags:
  --namespace-output KEY TF output for namespace (default: keycloak_release_namespace)
  --service-output KEY   TF output for service name (default: keycloak_service_name)
  --port-output KEY      TF output for service port (default: keycloak_service_port)

Output file format:
  KEYCLOAK_JWKS_URI, KEYCLOAK_ISSUER, KEYCLOAK_TOKEN_URL — all cluster-internal
  http URLs of the form http://<service>.<namespace>.svc.cluster.local:<port>/realms/<realm>/...
EOF
}

_run_keycloak() {
  local out="" identity_dir="" realm=""
  local ns_key="keycloak_release_namespace" svc_key="keycloak_service_name" port_key="keycloak_service_port"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)               out="$2";          shift 2 ;;
      --identity-dir)      identity_dir="$2"; shift 2 ;;
      --realm)             realm="$2";        shift 2 ;;
      --namespace-output)  ns_key="$2";       shift 2 ;;
      --service-output)    svc_key="$2";      shift 2 ;;
      --port-output)       port_key="$2";     shift 2 ;;
      --help)              _help_keycloak; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$out" ]]          && { echo "keycloak: --out is required" >&2; exit 1; }
  [[ -z "$identity_dir" ]] && { echo "keycloak: --identity-dir is required" >&2; exit 1; }
  [[ -z "$realm" ]]        && { echo "keycloak: --realm is required" >&2; exit 1; }

  local ns svc port base
  ns=$(read_tf_output_required "$identity_dir" "$ns_key" "identity")
  svc=$(read_tf_output_required "$identity_dir" "$svc_key" "identity")
  port=$(read_tf_output_required "$identity_dir" "$port_key" "identity")
  base="http://${svc}.${ns}.svc.cluster.local:${port}"

  write_file_secure "$out" 600 <<EOF
# Keycloak identity provider URLs (cluster-internal)
KEYCLOAK_JWKS_URI=${base}/realms/${realm}/protocol/openid-connect/certs
KEYCLOAK_ISSUER=${base}/realms/${realm}
KEYCLOAK_TOKEN_URL=${base}/realms/${realm}/protocol/openid-connect/token
EOF
  emit_ok "$out"
}

# ========================================================================
# Bundle: s3-config
# ========================================================================

_help_s3_config() {
  cat <<'EOF'
s3-config — S3 bucket name + region.
Anchored to: aws-eks-secure-s3.

Usage:
  render-bundle.sh s3-config --out FILE --data-dir DIR --region REGION
                            [--bucket-output KEY]

Required flags:
  --out FILE            Output .env file path
  --data-dir DIR        Data stack directory
  --region REGION       AWS region

Optional flags:
  --bucket-output KEY   TF output for bucket name (default: bucket_name)

Output file format:
  bucket-name=..., region=...
EOF
}

_run_s3_config() {
  local out="" data_dir="" region="" bucket_key="bucket_name"
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)            out="$2";        shift 2 ;;
      --data-dir)       data_dir="$2";   shift 2 ;;
      --region)         region="$2";     shift 2 ;;
      --bucket-output)  bucket_key="$2"; shift 2 ;;
      --help)           _help_s3_config; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$out" ]]      && { echo "s3-config: --out is required" >&2; exit 1; }
  [[ -z "$data_dir" ]] && { echo "s3-config: --data-dir is required" >&2; exit 1; }
  [[ -z "$region" ]]   && { echo "s3-config: --region is required" >&2; exit 1; }

  local bucket
  bucket=$(read_tf_output_required "$data_dir" "$bucket_key" "data")

  write_file_secure "$out" 600 <<EOF
bucket-name=$bucket
region=$region
EOF
  emit_ok "$out"
}

# ========================================================================
# Bundle: kafka-workload
# ========================================================================

_help_kafka_workload() {
  cat <<'EOF'
kafka-workload — Confluent Cloud workload credentials.
Anchored to: confluent-streaming-workload-access (workload_kafka_api_* + workload_schema_registry_api_* maps).

Usage:
  render-bundle.sh kafka-workload --out FILE --streaming-dir DIR --workload WORKLOAD_KEY

Required flags:
  --out FILE             Output .env file path
  --streaming-dir DIR    Streaming stack directory
  --workload KEY         Workload key (matches the per-workload map keys in TF outputs)

Skip behaviour: emits a skip if the streaming stack is not configured
(confluent_configured TF output is not "true") or if the workload key is
not found in the workload_* maps.

Output file format:
  bootstrap-servers=..., api-key=..., api-secret=..., schema-registry-url=...,
  schema-registry-api-key=..., schema-registry-api-secret=...
EOF
}

_run_kafka_workload() {
  local out="" streaming_dir="" workload=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)            out="$2";           shift 2 ;;
      --streaming-dir) streaming_dir="$2";  shift 2 ;;
      --workload)       workload="$2";      shift 2 ;;
      --help)           _help_kafka_workload; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$out" ]]           && { echo "kafka-workload: --out is required" >&2; exit 1; }
  [[ -z "$streaming_dir" ]] && { echo "kafka-workload: --streaming-dir is required" >&2; exit 1; }
  [[ -z "$workload" ]]      && { echo "kafka-workload: --workload is required" >&2; exit 1; }

  if ! (cd "$streaming_dir" && $TOFU output confluent_configured 2>/dev/null | grep -q "true"); then
    emit_skip "$(basename "$out") (streaming not configured)"
    return
  fi

  local kafka_bootstrap sr_url kafka_key kafka_secret sr_key sr_secret
  kafka_bootstrap=$(cd "$streaming_dir" && $TOFU output -raw kafka_bootstrap_servers 2>/dev/null || echo "")
  sr_url=$(cd "$streaming_dir" && $TOFU output -raw schema_registry_url 2>/dev/null || echo "")
  kafka_key=$(read_tf_output_map_value "$streaming_dir" workload_kafka_api_key_ids "$workload")
  kafka_secret=$(read_tf_output_map_value "$streaming_dir" workload_kafka_api_secrets "$workload")
  sr_key=$(read_tf_output_map_value "$streaming_dir" workload_schema_registry_api_key_ids "$workload")
  sr_secret=$(read_tf_output_map_value "$streaming_dir" workload_schema_registry_api_secrets "$workload")

  if [[ -z "$kafka_bootstrap" || -z "$kafka_key" ]]; then
    emit_skip "$(basename "$out") (workload '$workload' not found in streaming outputs)"
    return
  fi

  write_file_secure "$out" 600 <<EOF
bootstrap-servers=$kafka_bootstrap
api-key=$kafka_key
api-secret=$kafka_secret
schema-registry-url=$sr_url
schema-registry-api-key=$sr_key
schema-registry-api-secret=$sr_secret
EOF
  emit_ok "$out"
}

# ========================================================================
# Bundle: rds-ca-pair
# ========================================================================

_help_rds_ca_pair() {
  cat <<'EOF'
rds-ca-pair — Amazon RDS CA bundle PEM + pointer .env file.

Usage:
  render-bundle.sh rds-ca-pair --secure-dir DIR --prefix PREFIX [--url URL]

Required flags:
  --secure-dir DIR    Output directory (writes both files here)
  --prefix PREFIX     Filename prefix (e.g. staging-k8s)

Optional flags:
  --url URL           Override the Amazon RDS bundle URL (default: global bundle)

Output files:
  <secure-dir>/<prefix>-rds-ca-bundle.pem  (downloaded; chmod 600)
  <secure-dir>/<prefix>-rds-cert.env       (pointer to the PEM; chmod 600)
EOF
}

_run_rds_ca_pair() {
  local secure_dir="" prefix="" url=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --secure-dir) secure_dir="$2"; shift 2 ;;
      --prefix)     prefix="$2";     shift 2 ;;
      --url)        url="$2";        shift 2 ;;
      --help)       _help_rds_ca_pair; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$secure_dir" ]] && { echo "rds-ca-pair: --secure-dir is required" >&2; exit 1; }
  [[ -z "$prefix" ]]     && { echo "rds-ca-pair: --prefix is required" >&2; exit 1; }

  local pem="$secure_dir/${prefix}-rds-ca-bundle.pem"
  local cert="$secure_dir/${prefix}-rds-cert.env"

  if [[ -n "$url" ]]; then
    if download_rds_ca_bundle "$pem" "$url"; then emit_ok "$pem"
    else emit_skip "$(basename "$pem") (download failed from $url)"; fi
  else
    if download_rds_ca_bundle "$pem"; then emit_ok "$pem"
    else emit_skip "$(basename "$pem") (download failed from $RDS_CA_URL_DEFAULT)"; fi
  fi

  write_file_secure "$cert" 600 <<EOF
rds-ca-bundle.pem=.secure_files/${prefix}-rds-ca-bundle.pem
EOF
  emit_ok "$cert"
}

# ========================================================================
# Bundle: aws-arns (generic projection across stacks)
# ========================================================================

_help_aws_arns() {
  cat <<'EOF'
aws-arns — Project N TF outputs from N stacks into a single .env.

Usage:
  render-bundle.sh aws-arns --out FILE
                           --stack NAME=DIR [--stack NAME=DIR ...]
                           --emit KEY=NAME:OUTPUT[MAP_KEY] [--emit ... ...]
                           [--emit-fallback KEY=NAME:OUTPUT]

Required flags:
  --out FILE                      Output .env file path
  --stack NAME=DIR                Register a stack alias (repeatable)
  --emit KEY=NAME:OUTPUT          Emit a line `KEY=<output value>` reading from
                                  stack NAME's TF output OUTPUT (repeatable).
                                  Supports map(string) lookup via OUTPUT[MAP_KEY].

Optional flags:
  --emit-fallback KEY=NAME:OUTPUT Used only if a same-KEY --emit returned an
                                  empty value. Useful for cert resolution
                                  patterns: `--emit ACM_CERT_ARN=tls:my_cert
                                  --emit-fallback ACM_CERT_ARN=tls:cert`.
                                  Repeatable per KEY.

Each --emit reads its TF output. If empty AND a same-KEY --emit-fallback
is given, the fallback is tried. If still empty, the bundle exits 1.

Example:
  render-bundle.sh aws-arns --out aws.env \
    --stack tls=$TLS_DIR --stack data=$DATA_DIR --stack cloud=$CLOUD_DIR \
    --emit ACM_CERT_ARN=tls:certificate_arn \
    --emit IRSA_ROLE_ARN=data:my_service_irsa_role_arn \
    --emit KARPENTER_NODE_ROLE=cloud:karpenter_node_role_name
EOF
}

_run_aws_arns() {
  # Use parallel indexed arrays instead of associative arrays for bash 3.2
  # compatibility (macOS default).
  STACK_NAMES=()
  STACK_DIRS_INDEXED=()
  EMITS=()
  FALLBACK_KEYS=()
  FALLBACK_SPECS=()
  local out=""
  local kv
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)            out="$2"; shift 2 ;;
      --stack)
        kv="$2"; shift 2
        STACK_NAMES+=("${kv%%=*}")
        STACK_DIRS_INDEXED+=("${kv#*=}")
        ;;
      --emit)           EMITS+=("$2"); shift 2 ;;
      --emit-fallback)
        kv="$2"; shift 2
        FALLBACK_KEYS+=("${kv%%=*}")
        FALLBACK_SPECS+=("${kv#*=}")
        ;;
      --help)           _help_aws_arns; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$out" ]] && { echo "aws-arns: --out is required" >&2; exit 1; }
  [[ "${#EMITS[@]}" -eq 0 ]] && { echo "aws-arns: at least one --emit is required" >&2; exit 1; }

  local tmp; tmp=$(mktemp)
  # Bake $tmp into the trap command at definition time (double-quotes) so the
  # EXIT trap fires correctly even though $tmp is function-local — the trap
  # is global and would otherwise hit `unbound variable` under `set -u`.
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" EXIT

  echo "# AWS resource ARNs — rendered from one or more TF stack outputs" > "$tmp"
  local spec key rhs stack output map_key val fallback_spec
  for spec in "${EMITS[@]}"; do
    key="${spec%%=*}"
    rhs="${spec#*=}"
    read -r stack output map_key < <(_parse_emit_spec "$key=$rhs")
    val=$(_read_spec "$stack" "$output" "$map_key")
    if [[ -z "$val" ]]; then
      if fallback_spec=$(_lookup_fallback_spec "$key"); then
        read -r stack output map_key < <(_parse_emit_spec "$key=$fallback_spec")
        val=$(_read_spec "$stack" "$output" "$map_key")
        [[ -n "$val" ]] && emit_info "$key resolved via fallback ($stack:$output)"
      fi
    fi
    if [[ -z "$val" ]]; then
      fallback_spec=$(_lookup_fallback_spec "$key" || echo "")
      echo "Error: aws-arns: $key resolved to empty (spec: $spec${fallback_spec:+, fallback: $fallback_spec})" >&2
      exit 1
    fi
    echo "$key=$val" >> "$tmp"
  done

  cat "$tmp" | write_file_secure "$out" 600
  emit_ok "$out"
}

# ========================================================================
# Bundle: registry
# ========================================================================

_help_registry() {
  cat <<'EOF'
registry — GitLab container registry credentials from .credentials.gitlab.

Usage:
  render-bundle.sh registry --out FILE --secure-dir DIR

Required flags:
  --out FILE         Output .env file path
  --secure-dir DIR   Directory containing .credentials.gitlab

Skip behaviour: emits a skip if .credentials.gitlab is missing or does not
contain user= and password= lines.

Output file format:
  REGISTRY_USER=..., REGISTRY_TOKEN=...

Convention: this is a Tomshley CI/CD pattern. Other deployments may not
need this bundle.
EOF
}

_run_registry() {
  local out="" secure_dir=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --out)        out="$2";        shift 2 ;;
      --secure-dir) secure_dir="$2"; shift 2 ;;
      --help)       _help_registry; exit 0 ;;
      *) echo "Unknown flag: $1" >&2; exit 1 ;;
    esac
  done
  [[ -z "$out" ]]        && { echo "registry: --out is required" >&2; exit 1; }
  [[ -z "$secure_dir" ]] && { echo "registry: --secure-dir is required" >&2; exit 1; }

  local creds="$secure_dir/.credentials.gitlab"
  if [[ ! -f "$creds" ]]; then
    emit_skip "$(basename "$out") (no .credentials.gitlab in $secure_dir)"
    return
  fi

  local user pass
  user=$(grep -E '^user=' "$creds" | head -1 | cut -d= -f2-)
  pass=$(grep -E '^password=' "$creds" | head -1 | cut -d= -f2-)
  if [[ -z "$user" || -z "$pass" ]]; then
    emit_skip "$(basename "$out") (.credentials.gitlab missing user or password)"
    return
  fi

  write_file_secure "$out" 600 <<EOF
# GitLab Container Registry credentials for K8s imagePullSecrets (read-only pull)
REGISTRY_USER=$user
REGISTRY_TOKEN=$pass
EOF
  emit_ok "$out"
}

# ========================================================================
# --list / top-level dispatch
# ========================================================================

_print_list() {
  echo "Available bundles (each anchored to a root-modules-tf module):"
  echo ""
  printf "  %-16s  %-50s  %s\n" "BUNDLE" "MODULE-ANCHOR" "DESCRIPTION"
  printf "  %-16s  %-50s  %s\n" "------" "-------------" "-----------"
  local entry name anchor desc
  for entry in "${BUNDLE_CATALOG[@]}"; do
    name="${entry%%:*}"
    anchor="${entry#*:}"; anchor="${anchor%%:*}"
    desc="${entry##*:}"
    printf "  %-16s  %-50s  %s\n" "$name" "$anchor" "$desc"
  done
  echo ""
  echo "Run \`$(basename "$0") <bundle> --help\` for per-bundle flags."
}

_print_usage() {
  cat <<EOF
Usage: $(basename "$0") <bundle> [flags...]
       $(basename "$0") --list
       $(basename "$0") <bundle> --help

Run --list to see the available bundles.
EOF
}

# Initialise counters once for the single invocation.
init_render_counters

if [[ $# -eq 0 ]]; then
  _print_usage; exit 1
fi

bundle="$1"; shift

case "$bundle" in
  --list|list)        _print_list; exit 0 ;;
  --help|-h|help)     _print_usage; exit 0 ;;
  ci-deploy)          _run_ci_deploy "$@" ;;
  aurora-config)      _run_aurora_config "$@" ;;
  aurora-master)      _run_aurora_master "$@" ;;
  aurora-tenant)      _run_aurora_tenant "$@" ;;
  redis-config)       _run_redis_config "$@" ;;
  redis-auth)         _run_redis_auth "$@" ;;
  keycloak)           _run_keycloak "$@" ;;
  s3-config)          _run_s3_config "$@" ;;
  kafka-workload)     _run_kafka_workload "$@" ;;
  rds-ca-pair)        _run_rds_ca_pair "$@" ;;
  aws-arns)           _run_aws_arns "$@" ;;
  registry)           _run_registry "$@" ;;
  *)
    echo "Error: unknown bundle '$bundle'" >&2
    echo "Run \`$(basename "$0") --list\` to see available bundles." >&2
    exit 1
    ;;
esac
