# Examples

Two entry points cover everything. A repository calls one of them once and
passes arguments; it does not chain stages together itself.

| Entry point | For | Dispatches on |
| --- | --- | --- |
| [`deploy.yml`](../.github/workflows/deploy.yml) | Applications | `target: ec2 \| eks \| lambda \| static` |
| [`publish.yml`](../.github/workflows/publish.yml) | Libraries | `ecosystem: npm \| pypi \| maven` |

```yaml
jobs:
  ci-cd:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/deploy.yml@v1
    permissions:
      id-token: write
      contents: read
    with:
      target: ec2
      environment: ${{ github.ref_name == 'main' && 'prod' || 'dev' }}
      run_ci: true
      ci_language: node
      docker_image_name: billing-api
      s3_path: billing-api/builds
    secrets:
      IAM_ROLE_ARN: ${{ secrets.IAM_ROLE_ARN }}
      EC2_INSTANCE_ID: ${{ secrets.EC2_INSTANCE_ID }}
```

## Files

| Example | Stack | Target | Shows |
| --- | --- | --- | --- |
| [nodejs/deploy.yml](nodejs/deploy.yml) | Node.js | EC2 | Branch-to-environment mapping, manual dispatch, health check |
| [nestjs/deploy.yml](nestjs/deploy.yml) | NestJS | EC2 | Monorepo `app_path`, path filters, private CodeArtifact packages |
| [angular/deploy.yml](angular/deploy.yml) | Angular | S3 + CloudFront | Headless test defaults, Angular 17+ output path |
| [react/deploy.yml](react/deploy.yml) | React (Vite) | S3 + CloudFront | pnpm, three-way environment mapping |
| [nx/deploy.yml](nx/deploy.yml) | Nx monorepo | EKS + npm | App and library out of one repository |
| [java/deploy.yml](java/deploy.yml) | Java (Maven) | EKS + Maven | JDK matrix, Helm, tag-triggered publish |
| [python/deploy.yml](python/deploy.yml) | Python | Lambda + PyPI | arm64 container Lambda, alias for rollback |
| [publishing/release.yml](publishing/release.yml) | Library | CodeArtifact | npm, PyPI and Maven from one call |

## How mode works

Neither entry point needs branch conditions to decide what to do. Both read the
trigger and resolve a plan, which is printed to the job summary.

`deploy.yml`, input `mode` (default `auto`):

| Trigger | Runs |
| --- | --- |
| Pull request | CI only. Never touches an environment |
| Push, or manual dispatch | CI, then deploy |

Override with `mode: ci-only` or `mode: deploy`.

`publish.yml`, input `mode` (default `auto`):

| Trigger | Mode | Version |
| --- | --- | --- |
| Pull request | `verify` | Dry-run publish, throwaway version |
| Push to a branch | `snapshot` | `1.4.2-dev.87` — a prerelease, so `^1.4.0` will not resolve to it |
| Tag `v1.4.3` | `release` | `1.4.3`, from the tag |

Override with `mode: verify`, `snapshot` or `release`.

## Two calls, not one

A repository that ships both an application and a library uses both entry
points — see [nx](nx/deploy.yml), [java](java/deploy.yml) and
[python](python/deploy.yml). These are two products with two lifecycles, and
collapsing them would mean one job that sometimes publishes and sometimes does
not.

## Patterns worth copying

**Environment from branch**, inline:

```yaml
environment: ${{ (github.ref_name == 'main' && 'prod') || (github.ref_name == 'staging' && 'stg') || 'dev' }}
```

**Concurrency.** Cancel superseded pull request builds; never cancel a
deployment mid-flight:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

**Permissions on the calling job.** They do not inherit into a called workflow:

```yaml
permissions:
  id-token: write
  contents: read
```

**Pin to `@v1`**, not `@main`. See
[conventions.md](../docs/conventions.md#versioning).

**Call the entry point from your own workflow, not from another reusable
workflow.** `deploy.yml` → `pipeline-*` → `build-*` already uses all four levels
GitHub allows. If you need to wrap it, call the `pipeline-*` workflow directly.

## Going below the entry points

The entry points cover the common shapes. When one does not fit, the stage
workflows underneath are still public and composable — see the catalogue in the
[README](../README.md). Reasons to drop down:

- A build that fans out to several images or clusters in one run
- A deployment sequenced against something the entry point does not know about
- A target combination the `target` input does not offer

## Adding rollback

Rollback stays a separate, manually triggered workflow — it is deliberately not
something an automatic pipeline can reach:

```yaml
name: Rollback

on:
  workflow_dispatch:
    inputs:
      environment:
        type: choice
        options: [dev, uat, prod]
      version:
        description: "Version to restore, shown in the deployment job summary"
        required: true

jobs:
  rollback:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/rollback-ec2.yml@v1
    permissions:
      id-token: write
      contents: read
    with:
      environment: ${{ inputs.environment }}
      docker_image_name: billing-api
      s3_path: billing-api/builds
      version: ${{ inputs.version }}
    secrets:
      IAM_ROLE_ARN: ${{ secrets.IAM_ROLE_ARN }}
      EC2_INSTANCE_ID: ${{ secrets.EC2_INSTANCE_ID }}
      AWS_SECRETS_ARN: ${{ secrets.AWS_SECRETS_ARN }}
```

For EKS use `rollback-eks.yml`; for Lambda, `rollback-lambda.yml`, which
repoints the alias and is close to instant.
