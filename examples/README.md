# Examples

Working starting points. Copy the closest one into your repository's
`.github/workflows/`, change the names, and delete what you do not need.

| Example | Stack | Target | Shows |
| --- | --- | --- | --- |
| [nodejs/deploy.yml](nodejs/deploy.yml) | Node.js | EC2 | Branch-to-environment mapping, Node matrix, health check |
| [nestjs/deploy.yml](nestjs/deploy.yml) | NestJS | EC2 | Monorepo `app_path`, path filters, private CodeArtifact packages |
| [angular/deploy.yml](angular/deploy.yml) | Angular | S3 + CloudFront | Headless test defaults, Angular 17+ output path |
| [react/deploy.yml](react/deploy.yml) | React (Vite) | S3 + CloudFront | pnpm, three-way environment mapping |
| [nx/deploy.yml](nx/deploy.yml) | Nx monorepo | EKS + npm | `nx affected` on PRs, full build on merge, library publishing |
| [java/deploy.yml](java/deploy.yml) | Java (Maven) | EKS + Maven | JDK matrix, Helm deployment, tag-triggered publish |
| [python/deploy.yml](python/deploy.yml) | Python | Lambda + PyPI | Version matrix, arm64 container Lambda, alias for rollback |

## Patterns worth copying

**Environment from branch.** Either resolve it in a small job (see
[nodejs](nodejs/deploy.yml)) when the mapping has more than two cases, or inline
the expression when it is simple:

```yaml
environment: ${{ github.ref_name == 'main' && 'prod' || 'dev' }}
```

**Concurrency.** Cancel superseded pull request builds; never cancel a
deployment mid-flight:

```yaml
concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
```

**Permissions on the calling job.** They do not inherit into a called workflow.
Any job calling something that touches AWS needs:

```yaml
permissions:
  id-token: write
  contents: read
```

**Pin to `@v1`.** Not `@main`. See
[conventions.md](../docs/conventions.md#versioning).

## Adding rollback

Every example builds artifacts that can be rolled back to. Add a manually
triggered workflow so the path is available before you need it:

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

For EKS use `rollback-eks.yml`; for Lambda, `rollback-lambda.yml`, which just
repoints the alias and is close to instant.
