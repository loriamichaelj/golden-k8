# Changelog

Releases follow semantic versioning. `vX` always points at the newest `vX.Y.Z`.
A breaking change to the parameter file bumps both its `apiVersion` and the
major version.

## v1.0.0 (2026-11-23)

First release. One parameter file (`golden.k8/v1alpha1`) takes an environment
from network to cluster to observability to a running sample app.

- **Parameter file:** JSON Schema with editor completion, per-provider defaults,
  cross-field rules, normalized into one config by `make config`.
- **Adapters:** `local` (kind, end to end), `existing` (a cluster on this machine,
  behind guardrails), and `aws` (VPC + EKS), `gcp` (VPC + GKE), `azure`
  (VNet + AKS), which are validated and tested against mocked providers and never
  applied. Every adapter emits the same outputs contract, checked by a shared
  parity test. Cloud API endpoints are private unless you list allowed ranges.
- **Platform:** Ansible installs Envoy Gateway (one shared Gateway API entry
  point) and kube-prometheus-stack (`lite` profile under 1.5 GB), idempotently.
- **Sample app:** a Go service with Prometheus metrics, a distroless image under
  20 MB, Kustomize overlays per provider, a Grafana dashboard and smoke tests.
- **Pipeline:** a reusable workflow (`golden-path.yml`) that callers pin with
  `@v1`; `make render` shows what any environment would get, schema-checked.
- **Checks:** lint, config contract, Terraform tests, guardrails, kubeconform,
  Trivy (gating) and Checkov with results in code scanning, and gitleaks.
