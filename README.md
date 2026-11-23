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

make up      # kind cluster → image → platform → app (environments/local.yaml)
make smoke   # check the app end to end
make down    # destroy it
```

Then open http://hello.localtest.me and http://grafana.localtest.me (`make grafana` prints the login).

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

Editors with the YAML language server (e.g. VS Code + `redhat.vscode-yaml`) get autocomplete and inline errors from `schema/golden.schema.json`.

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
make bootstrap   # Ansible: preflight → render → namespaces → Envoy Gateway → observability → app
```

Ansible only applies what it renders into `build/rendered/` from the config, the infrastructure outputs and the data in `k8s/` (Helm releases, namespaces, templates, the app overlays). Every tool is pinned to the cluster in `build/contract.json`; nothing falls back to your default kubeconfig. Helm also runs with its own config and cache under `build/helm/`, never your personal Helm repos.

- **Traffic:** Gateway API with Envoy Gateway. One shared `Gateway` (`golden-gateway`); apps attach `HTTPRoute`s. On kind it listens on `127.0.0.1:80`.
- **Namespaces:** labelled `golden-k8/managed=true`. Workload namespaces get a ResourceQuota, LimitRange defaults, default-deny NetworkPolicies (DNS, gateway and Prometheus traffic allowed) and the `restricted` Pod Security standard.

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
- **metrics-server** (kind only; managed clouds ship their own) feeds the app's HorizontalPodAutoscaler.

## Sample app

A small Go service in `app/` (`net/http`, `log/slog` JSON logs, `prometheus/client_golang`):

- **Endpoints:** `/` (hello + build info), `/healthz`, `/readyz` (turns 503 on SIGTERM, before the listener closes) and `/metrics` (`hello_http_requests_total`, `hello_http_request_duration_seconds`, …).
- **Image:** multi-stage build to `distroless/static:nonroot`, about 15 MB. `make image` fails at 20 MB or more and loads the image straight into kind. Nothing is pushed to a registry.
- **Manifests** (`k8s/app/`): a Kustomize base with the Deployment, Service, HTTPRoute, HPA, PDB, ServiceMonitor and Grafana dashboard, plus one overlay per provider.
  - The Deployment runs non-root with a read-only root filesystem, probes and resource limits.
  - The cloud overlays also spread replicas across zones.
  - Bootstrap renders a generated overlay on top. It sets the image, the HPA minimum from `spec.app.replicas`, and the hostname from `spec.app.expose.host`.
- **Dashboard:** `golden-k8 / hello` in Grafana shows request rate, error ratio, latency quantiles, replicas, CPU and memory.

```sh
make test-app         # go test -race
make test-manifests   # every overlay through kubeconform (strict, pinned Kubernetes + CRD schemas)
make smoke            # app via the Gateway, Prometheus scrapes it, request metric recorded, dashboard provisioned, HPA has metrics
```

## Render without a cluster

```sh
make render ENV=environments/aws-example.yaml
```

This renders everything the environment would get, for any provider: the platform manifests, every Helm release (`helm template` with the rendered values) and the app. All of it is validated with kubeconform (strict, against pinned Kubernetes and CRD schemas). The output is plain YAML in `build/rendered/`, plus a summary of resources per file. Without a cluster, the outputs contract is a placeholder with the provider's gateway shape.

## The golden path in CI

`.github/workflows/golden-path.yml` is a reusable workflow. Call it from your own repository with your parameter file:

```yaml
jobs:
  environment:
    uses: <owner>/golden-k8/.github/workflows/golden-path.yml@<ref>
    with:
      config-file: environments/team-a.yaml
      apply: true   # provider local only: run it end to end on kind
```

| Job | What it does |
|---|---|
| `config` | Validates and normalizes the parameter file. It uploads `config.json` as an artifact and forces the `lite` profile. |
| `terraform` | Validates the provider's stack and runs every Terraform test, with mocked providers. |
| `deploy + smoke (kind)` | *(local, `apply: true`)* Creates the kind cluster, renders and validates, builds and loads the image, and bootstraps twice (the second run must change nothing). Then it runs the smoke and observability checks and always tears the cluster down. It runs in the `ci` environment. |
| `render + schema check` | *(every other environment)* Runs `make render`. It needs no cluster and no credentials. |

- **Job summaries:** each job writes a summary to the run page: Terraform results, rendered resource counts, image size, smoke results and observability memory.
- **Checkouts:** the parameter file comes from your repository, and golden-k8 is checked out a second time at `golden-ref`. When the caller is golden-k8 itself (or a repository created from the template), the second checkout is skipped.
- **This repository's CI:** it calls the workflow by local path for the local environment and for the three cloud examples. One of those calls forces the second checkout, so the path other repositories take stays tested.

## Repository layout

```
environments/   parameter files, one per environment
schema/         parameter file JSON Schema + defaults
terraform/      provider adapters (modules/), root stacks (stacks/), tests
ansible/        bootstrap and smoke playbooks, roles
k8s/            platform data (Helm releases, templates) and sample app manifests (Kustomize)
app/            sample Go service
.github/        CI, reusable workflow, composite actions
```

## Tooling

Every tool version is pinned in [`mise.toml`](mise.toml) and locked with checksums in `mise.lock`. Local runs and CI use the same binaries.

## License

[MIT](LICENSE)
