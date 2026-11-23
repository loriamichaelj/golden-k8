# golden-k8

A cloud-agnostic **golden-path template** that takes a greenfield environment from nothing to a running, observable sample app, driven by a single parameter file:

```
network → Kubernetes cluster → observability → sample app
```

Built with GitHub Actions, Terraform, Ansible and Kubernetes manifests. It targets **AWS, GCP, Azure**, a **local kind cluster**, or an **existing cluster** through one interface.

> **Status: pre-alpha.** The repository foundation is in place; the features below are being built incrementally.

## Principles

- **One parameter file** describes an environment. Everything else is derived from it.
- **Cloud-agnostic.** Only the network + cluster layer is provider-specific. Observability and apps are portable open-source components.
- **Zero cost by default.** The full pipeline runs end to end on a local kind cluster, both on your machine and in CI. Cloud adapters are validated and tested against mocked providers. Nothing is provisioned in any cloud account, and no credentials are needed.
- **Reusable two ways.** Call the reusable workflow from your own repo, or create a new repo from this template.

## Quick start

Requirements: [mise](https://mise.jdx.dev) and a Docker engine (Docker Desktop, OrbStack, Colima, …).

```sh
make tools   # install the pinned tool versions from mise.toml
make hooks   # install the pre-commit hook
make lint    # run every linter and scanner
make help    # list all targets
```

## The parameter file

An environment is one YAML file in `environments/`. Only `metadata.name` and `spec.provider` are required (plus `region` for clouds); everything else has a default in `schema/defaults/`.

```yaml
# yaml-language-server: $schema=../schema/golden.schema.json
apiVersion: golden.k8/v1alpha1
kind: Environment
metadata:
  name: local
spec:
  provider: local   # local | existing | aws | gcp | azure
```

```sh
make config ENV=environments/local.yaml   # validate + merge defaults → build/config.json
make test-config                          # schema test fixtures + example environments
```

## Local cluster

```sh
make infra-up     # kind cluster for ENV (default environments/local.yaml) → build/contract.json
make infra-down   # destroy it
```

The cluster runs on your local Docker engine. The API server and the gateway port listen on `127.0.0.1` only. Cloud environments (`aws`/`gcp`/`azure`) are refused: they are validated and tested with mocked providers, never applied.

```sh
make test-terraform   # Terraform tests for every module and stack (no cloud, no Docker)
```

## Platform bootstrap

```sh
make bootstrap   # Ansible: preflight → render → namespaces → Envoy Gateway → observability
```

Ansible only applies what it renders into `build/rendered/` from the config, the infrastructure outputs and the data in `k8s/platform/` (Helm releases, namespaces, templates). Every tool is pinned to the cluster in `build/contract.json`; nothing falls back to your default kubeconfig.

- **Traffic:** Gateway API with Envoy Gateway. One shared `Gateway` (`golden-gateway`); apps attach `HTTPRoute`s. On kind it listens on `127.0.0.1:80`.
- **Namespaces:** labelled `golden-k8/managed=true`. Workload namespaces get a ResourceQuota, LimitRange defaults, default-deny NetworkPolicies (DNS and gateway traffic allowed) and the `restricted` Pod Security standard.

## Observability

`kube-prometheus-stack` in the `monitoring` namespace: Prometheus, Grafana, kube-state-metrics and node-exporter. Prometheus picks up `ServiceMonitor`s and rules from every namespace.

```sh
make grafana               # URL and admin login (default: http://grafana.localtest.me)
make check-observability   # Grafana via the Gateway, every Prometheus target up, memory budget
```

- **Profiles** (`spec.observability.profile`):
  - `lite` (default): no Alertmanager, trimmed rules, small requests, under 1.5 GB.
  - `standard`: adds Alertmanager and the full rule set.
  - CI always uses `lite` and warns when the parameter file asks for something else.
- **Grafana** is served on the shared Gateway at `spec.observability.expose.host`. `*.localtest.me` resolves to `127.0.0.1`, so the local URL works without editing `/etc/hosts`. The admin password is generated in the cluster (Secret `monitoring/grafana-admin`) on the first bootstrap. It is never written to the repo or the rendered values.
- **Retention:** `spec.observability.retentionDays` (default 2), capped by size.

Editors with the YAML language server (e.g. VS Code + `redhat.vscode-yaml`) get autocomplete and inline errors from `schema/golden.schema.json`.

## Repository layout

```
environments/   parameter files, one per environment
schema/         parameter file JSON Schema + defaults
terraform/      provider adapters (modules/), root stacks (stacks/), tests
ansible/        platform bootstrap playbooks and roles
k8s/            platform Helm values and sample app manifests
app/            sample Go service
.github/        CI, reusable workflow, composite actions
```

## Tooling

Every tool version is pinned in [`mise.toml`](mise.toml) and locked with checksums in `mise.lock`. Local runs and CI use the same binaries.

## License

[MIT](LICENSE)
