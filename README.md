# sgx-github-actions

Centralised CI/CD for the organisation. Application repositories describe *what*
they want deployed; this repository owns *how* it happens.

```yaml
jobs:
  deploy:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/pipeline-ec2.yml@v1
    permissions:
      id-token: write
      contents: read
    with:
      environment: prod
      docker_image_name: billing-api
      s3_path: billing-api/builds
    secrets:
      IAM_ROLE_ARN: ${{ secrets.IAM_ROLE_ARN }}
      EC2_INSTANCE_ID: ${{ secrets.EC2_INSTANCE_ID }}
      AWS_SECRETS_ARN: ${{ secrets.AWS_SECRETS_ARN }}
```

Start with [docs/onboarding.md](docs/onboarding.md), then copy the closest file
from [examples/](examples/).

---

## Structure

Three layers. Pipelines chain stages; stages own an environment and a runner;
composite actions do one task inside somebody else's job.

```
Pipelines   pipeline-ec2 · pipeline-eks · pipeline-lambda · pipeline-static
Stages      ci-* · build-* · publish-* · deploy-* · rollback-*
Actions     actions/aws-oidc-auth · actions/ssm-exec · actions/docker-build · …
```

Full reasoning in [docs/architecture.md](docs/architecture.md).

---

## Pipelines

Call one of these and you get an end-to-end deployment.

| Workflow | Does |
| --- | --- |
| [`pipeline-ec2.yml`](.github/workflows/pipeline-ec2.yml) | Build → S3 → load onto EC2 over SSM → start with Compose |
| [`pipeline-eks.yml`](.github/workflows/pipeline-eks.yml) | Build → ECR → roll out to EKS via kubectl, kustomize or Helm |
| [`pipeline-lambda.yml`](.github/workflows/pipeline-lambda.yml) | Build → ECR → update the function → move the alias |
| [`pipeline-static.yml`](.github/workflows/pipeline-static.yml) | Build → S3 sync → CloudFront invalidation |

## Stages

Compose these yourself when a pipeline does not fit.

**Build and test**

| Workflow | Covers |
| --- | --- |
| [`ci-node.yml`](.github/workflows/ci-node.yml) | Node.js, NestJS, Angular, React, Nx. Version matrix, `nx affected`, artifact upload |
| [`ci-java.yml`](.github/workflows/ci-java.yml) | Maven and Gradle. JDK matrix, test reports |
| [`ci-python.yml`](.github/workflows/ci-python.yml) | Version matrix, ruff and pytest by default, optional sdist/wheel |

**Package**

| Workflow | Produces |
| --- | --- |
| [`build-docker-ecr.yml`](.github/workflows/build-docker-ecr.yml) | Image in ECR, tagged by version, SHA and `latest` |
| [`build-docker-s3.yml`](.github/workflows/build-docker-s3.yml) | Image tarball in S3, both moving and immutable copies |

**Publish**

| Workflow | Target |
| --- | --- |
| [`publish-npm.yml`](.github/workflows/publish-npm.yml) | CodeArtifact npm |
| [`publish-pypi.yml`](.github/workflows/publish-pypi.yml) | CodeArtifact PyPI |
| [`publish-maven.yml`](.github/workflows/publish-maven.yml) | CodeArtifact Maven |

**Deploy**

| Workflow | Target |
| --- | --- |
| [`deploy-ec2-load-docker.yml`](.github/workflows/deploy-ec2-load-docker.yml) | Pull the tarball from S3 onto the instance and load it |
| [`deploy-ec2-start-container.yml`](.github/workflows/deploy-ec2-start-container.yml) | Write config, restart the container, optional health check |
| [`deploy-eks.yml`](.github/workflows/deploy-eks.yml) | EKS, with rollout wait and failure diagnostics |
| [`deploy-lambda.yml`](.github/workflows/deploy-lambda.yml) | Lambda, zip or container image, with alias management |
| [`deploy-s3-cloudfront.yml`](.github/workflows/deploy-s3-cloudfront.yml) | Static site, with correct cache headers per file type |

**Roll back**

| Workflow | Mechanism |
| --- | --- |
| [`rollback-ec2.yml`](.github/workflows/rollback-ec2.yml) | Restore an archived image by version |
| [`rollback-eks.yml`](.github/workflows/rollback-eks.yml) | `rollout undo`, or pin an explicit image |
| [`rollback-lambda.yml`](.github/workflows/rollback-lambda.yml) | Repoint the alias at an earlier version |

## Composite actions

Usable directly from any job:

```yaml
- uses: Ennovative-Genix/sgx-github-actions/actions/aws-oidc-auth@v1
  with:
    role-arn: ${{ secrets.IAM_ROLE_ARN }}
    fallback-region: ${{ vars.AWS_REGION }}
```

| Action | Does |
| --- | --- |
| [`actions/aws-oidc-auth`](actions/aws-oidc-auth) | Resolve the region and assume a role via OIDC. No stored keys |
| [`actions/ssm-exec`](actions/ssm-exec) | Run commands on an instance over SSM and wait, with `jq`-built payloads |
| [`actions/docker-build`](actions/docker-build) | Buildx with a per-image GHA layer cache; load locally or push |
| [`actions/ecr-login`](actions/ecr-login) | Authenticate Docker to ECR, optionally creating the repository |
| [`actions/s3-image-upload`](actions/s3-image-upload) | `docker save` to S3, immutable copy first |
| [`actions/compute-version`](actions/compute-version) | One version per run, from tag, manifest or run number |
| [`actions/codeartifact-login`](actions/codeartifact-login) | Configure npm, pip, twine, Maven or Gradle against CodeArtifact |
| [`actions/setup-node`](actions/setup-node) | Node with npm/yarn/pnpm caching and a lockfile-faithful install |
| [`actions/setup-python`](actions/setup-python) | Python with pip caching, requirements or pyproject |
| [`actions/setup-java`](actions/setup-java) | JDK with Maven/Gradle caching and a generated `settings.xml` |
| [`actions/runner-disk-cleanup`](actions/runner-disk-cleanup) | Reclaim runner disk **inside** the job that needs it |

---

## Configuration

Set per GitHub Environment, not per repository — that is what makes `dev` and
`prod` differ without any branching in the workflow.

| Variable | Needed for |
| --- | --- |
| `AWS_REGION` | Everything. Deployments fail fast without it rather than guessing |
| `S3_BUILD_BUCKET` | EC2 path |
| `PORT_MAPPING` | EC2 path |
| `CLOUDWATCH_LOG_GROUP`, `CLOUDWATCH_LOG_STREAM` | EC2 path, optional |
| `STATIC_SITE_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID` | Static path |

| Secret | Needed for |
| --- | --- |
| `IAM_ROLE_ARN` | Everything |
| `EC2_INSTANCE_ID` | EC2 path |
| `AWS_SECRETS_ARN` | EC2 path, when the container needs a `.env` |

Full setup, including the IAM trust policy: [docs/onboarding.md](docs/onboarding.md).

## Versioning

Pin to `@v1`. It moves forward within the major line, so fixes arrive
automatically and breaking changes cannot.

| Ref | Moves | Use for |
| --- | --- | --- |
| `@v1` | Within the major line | **Default** |
| `@v1.4.2` | Never | Production-critical or regulated repositories |
| `@main` | Every merge | This repository's own testing only |

Details, and how to cut a release: [docs/conventions.md](docs/conventions.md#versioning).

## Security

- **No stored AWS credentials.** GitHub OIDC is exchanged for short-lived STS credentials per run
- **Roles scoped to `repo:<org>/<repo>:environment:<env>`**, so a role usable in `prod` requires a job that passed `prod`'s protection rules
- **No inbound access to instances.** Everything travels as an SSM document
- **Runtime secrets stay in Secrets Manager**, fetched at deploy time
- **No `secrets: inherit`.** Every workflow names exactly what it needs
- **No `${{ }}` interpolated into shell bodies.** Values arrive through `env:`

Reasoning: [docs/contracts.md](docs/contracts.md).

---

## Contributing

`validate.yml` runs actionlint, shellcheck, YAML parsing, internal reference
consistency, and a check that every workflow and action is documented. It must
pass before merge — a break here breaks every repository in the organisation.

See [CONTRIBUTING.md](CONTRIBUTING.md) and
[docs/conventions.md](docs/conventions.md).

## Documentation

| Document | Answers |
| --- | --- |
| [architecture.md](docs/architecture.md) | How it fits together, and why |
| [conventions.md](docs/conventions.md) | Naming, branching, versioning, coding standards |
| [contracts.md](docs/contracts.md) | Designing inputs, outputs, secrets, permissions |
| [decision-matrix.md](docs/decision-matrix.md) | Reusable workflow, composite action, or JavaScript action? |
| [onboarding.md](docs/onboarding.md) | Wiring up a new repository |
| [pitfalls.md](docs/pitfalls.md) | Anti-patterns to avoid |
| [examples/](examples/) | Working files to copy |

---

Maintained by Platform Engineering · Navdeep Singh <navdeep.singh@solugenix.com>
