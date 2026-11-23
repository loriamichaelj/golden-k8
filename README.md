# golden-k8

[![ci](https://github.com/loriamichaelj/golden-k8/actions/workflows/ci.yml/badge.svg)](https://github.com/loriamichaelj/golden-k8/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/loriamichaelj/golden-k8)](https://github.com/loriamichaelj/golden-k8/releases)

A cloud-agnostic **golden path**: one parameter file takes an environment from nothing to a running, observable app.

```
network → Kubernetes cluster → observability → sample app
```

Built with GitHub Actions, Terraform, Ansible and Kubernetes manifests, for **AWS, GCP, Azure**, a **local kind cluster** or an **existing cluster**.

- **Zero cost.** The full pipeline runs end to end on kind, locally and in CI. Cloud adapters are tested against mocked providers and never applied: no cloud account or credentials needed.
- **Portable.** Only the network and cluster layer is provider-specific. Everything above it (Envoy Gateway, kube-prometheus-stack, the app) is the same everywhere.
- **Reusable.** Call the workflow from your repository with `@v1`, or create a repository from this template.

## Quick start

Requires [mise](https://mise.jdx.dev) and a Docker engine (Docker Desktop, OrbStack, Colima, …).

```sh
make tools   # pinned tool versions from mise.toml
make up      # kind cluster → app image → platform → app
make smoke   # end-to-end checks
make down    # destroy the cluster
```

Then open http://hello.localtest.me and http://grafana.localtest.me (`make grafana` prints the login). `make help` lists every target.

## The parameter file

One YAML file per environment, in `environments/`. Only `metadata.name` and `spec.provider` are required (plus `region` for clouds); defaults live in `schema/defaults/`, and editors get completion from the JSON Schema.

```yaml
# yaml-language-server: $schema=../schema/golden.schema.json
apiVersion: golden.k8/v1alpha1
kind: Environment
metadata:
  name: dev
spec:
  provider: local   # local | existing | aws | gcp | azure
```

| Provider | What it does |
|---|---|
| `local` | kind cluster on your Docker engine, end to end (`make up`). |
| `existing` | Installs onto a cluster on this machine, such as OrbStack's (`CONFIRM_EXISTING=yes`). Remote clusters are always refused, and `make down` removes only what golden-k8 installed. |
| `aws` / `gcp` / `azure` | VPC + EKS / GKE / AKS, validated, mock-tested and rendered only. API endpoints are private unless you list allowed ranges. |

`make render ENV=environments/aws-example.yaml` shows everything an environment would get, schema-checked, without a cluster.

## Use it from your repository

```yaml
jobs:
  dev:
    uses: loriamichaelj/golden-k8/.github/workflows/golden-path.yml@v1
    with:
      config-file: environments/dev.yaml
      apply: true   # provider local: runs end to end on kind in the runner
```

Each run validates the parameter file, runs the Terraform tests, then either deploys to kind with smoke tests or renders and schema-checks the manifests, with summaries on the run page. See [`examples/consumer/`](examples/consumer/) for a complete caller repository.

`@v1` follows compatible releases; pin an exact tag (`@v1.0.0`) to control upgrades. Changes are in [`CHANGELOG.md`](CHANGELOG.md).

## Checks

```sh
make validate   # lint, config contract, Terraform (mocked), guardrails, app tests, manifests
make security   # Trivy (fails on HIGH/CRITICAL) + Checkov, results in GitHub code scanning
```

## Layout

```
environments/   parameter files
schema/         JSON Schema and defaults
terraform/      provider modules, root stacks, tests
ansible/        bootstrap, smoke and teardown playbooks
k8s/            platform releases and templates, app manifests (Kustomize)
app/            sample Go service
examples/       a caller repository
```

Tool versions are pinned in [`mise.toml`](mise.toml) and used both locally and in CI.

## License

[MIT](LICENSE)
