# Roadmap

This document outlines **intent**, not commitments.

## Completed (v1.0.0)

- GKE production hardening: data source removal, implicit dependency ordering
- GKE networking parameterization (subnet, services, pods, master, IPv6)
- Generic GKE nodepool module with labels, taints, kubelet_config
- Full AWS EKS module suite (VPC, cluster, nodegroup, Karpenter prereqs, IRSA)
- Reference examples for GKE and EKS full stacks
- OSS documentation and branding
- CI/CD modernization with auto-discovery publishing

## Short Term

- Validate all modules with `terraform validate` in CI
- Add Snyk IaC scanning to CI pipeline
- Per-module README with input/output tables

## Medium Term

- GKE Autopilot module
- Multi-region VPC peering module
- Karpenter Helm operator template (separate repo, consumes prereqs outputs)

## Long Term

- Broader OSS adoption
- Community contributions and module registry publishing

The roadmap may evolve as requirements and priorities change.
