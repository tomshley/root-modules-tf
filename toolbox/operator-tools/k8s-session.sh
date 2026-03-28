#!/usr/bin/env bash
# k8s-session.sh — Auto-discover the EKS cluster and update kubeconfig.
#
# Prerequisites: AWS credentials must already be loaded (e.g. via aws-session.sh).
#
# Usage:
#   source /path/to/operator-tools/aws-session.sh /path/to/.secure_files/staging-us-east-1-cloud.env
#   source /path/to/operator-tools/k8s-session.sh
#
# This discovers the first EKS cluster in the current AWS_REGION and
# runs `aws eks update-kubeconfig` so kubectl is pointed at it.

set -euo pipefail

if [[ -z "${AWS_REGION:-}" ]]; then
  echo "ERROR: AWS_REGION is not set. Source aws-session.sh first." >&2
  return 1 2>/dev/null || exit 1
fi

EKS_CLUSTER="$(aws eks list-clusters --region "${AWS_REGION}" --query 'clusters[0]' --output text 2>/dev/null || true)"

if [[ -z "$EKS_CLUSTER" || "$EKS_CLUSTER" == "None" ]]; then
  echo "ERROR: No EKS cluster found in ${AWS_REGION}" >&2
  return 1 2>/dev/null || exit 1
fi

echo "Discovered EKS cluster: ${EKS_CLUSTER}"
aws eks update-kubeconfig --name "$EKS_CLUSTER" --region "${AWS_REGION}"
echo "kubectl context updated. Verifying access:"
kubectl cluster-info --context "$(kubectl config current-context)" 2>&1 | head -2
