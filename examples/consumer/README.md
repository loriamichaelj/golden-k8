# Example consumer repository

A team repository that runs its environments through golden-k8. It holds only
parameter files and one workflow; Terraform, Ansible and the manifests come from
golden-k8 at the version the workflow pins (`@v1`).

```
.github/workflows/environments.yml   calls golden-k8's reusable workflow, one job per environment
environments/dev.yaml                provider local: runs end to end on kind in CI
environments/prod-aws.yaml           provider aws: validated, mock-tested and rendered only
```

## Use it

1. Copy `.github/workflows/environments.yml` and `environments/` into your repository.
2. Edit the parameter files. Your editor validates and completes them against the schema named on their first line.
3. Push. Each environment becomes a job group on the run page, with summaries of the Terraform tests, the rendered resources and, for `dev`, the smoke tests and the observability memory budget.

## Versions

- `@v1` follows the latest 1.x release; it never makes breaking changes to the parameter file. Pin an exact release (`@v1.0.0`) to control upgrades.
- The workflow checks out golden-k8 at the same release, so the workflow and the Terraform, Ansible and manifests it runs always match.

## What runs where

- **`dev` (provider local, `apply: true`):** the `deploy + smoke (kind)` job runs in your repository's `ci` environment. GitHub creates that environment on the first run; add protection rules to it if you want approvals.
- **`prod` (cloud):** the `render + schema check` job. No credentials are used or needed. golden-k8 refuses to apply cloud environments.
