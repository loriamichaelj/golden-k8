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
