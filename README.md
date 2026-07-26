# sgx-github-actions

Centralised CI/CD for the organisation. Application repositories describe _what_
they want deployed; this repository owns _how_ it happens.

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
      AWS_SECRETS_ARN: ${{ secrets.AWS_SECRETS_ARN }}
```

That is the whole file. A pull request runs CI and stops; a push runs CI and
deploys. Start with [docs/onboarding.md](docs/onboarding.md), then copy the
closest file from [examples/](examples/).

---

## Entry points

Almost every repository needs exactly one of these, called once.

| Workflow                                       | For          | Dispatches on                            |
| ---------------------------------------------- | ------------ | ---------------------------------------- |
| [`deploy.yml`](.github/workflows/deploy.yml)   | Applications | `target: ec2 \| eks \| lambda \| static` |
| [`publish.yml`](.github/workflows/publish.yml) | Libraries    | `ecosystem: npm \| pypi \| maven`        |

Both read the trigger to decide what to do — pull request verifies, push
deploys or publishes a snapshot, tag publishes a release — and print the
resolved plan to the job summary. Override with the `mode` input.

## ❗All Inputs, Secrets and Outputs❗

<details>
<summary><b><code>deploy.yml</code> — all inputs, secrets and outputs</b></summary>

Only `target` and `environment` are required. Everything else is optional, and
inputs outside the "Always" group are read only by the targets listed.

**Always**

| Input              | Type   | Default | Description                                                                                                                                        |
| ------------------ | ------ | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `target`           | string | —       | **Required.** `ec2`, `eks`, `lambda` or `static`.                                                                                                  |
| `environment`      | string | —       | **Required.** GitHub environment: `dev`, `qa`, `uat`, `stg`, `prod`. Supplies the AWS region, bucket names and approval rules.                     |
| `mode`             | string | `auto`  | `auto`, `ci-only` or `deploy`. `auto` runs CI without deploying on a pull request, and both otherwise.                                             |
| `app_path`         | string | `.`     | Application directory, relative to the repository root.                                                                                            |
| `aws_region`       | string | `""`    | Overrides the environment's `AWS_REGION`. **Required when `run_ci` pulls from CodeArtifact**, because CI jobs have no environment to read it from. |
| `version_strategy` | string | `auto`  | `auto`, `tag`, `manifest` or `run-number`. See [version strategies](#version-strategies).                                                          |

**CI** — runs before the deployment. Skipped for `static`, whose pipeline already builds and tests.

| Input                       | Type    | Default | Description                                                        |
| --------------------------- | ------- | ------- | ------------------------------------------------------------------ |
| `run_ci`                    | boolean | `false` | Lint, test and build before deploying.                             |
| `ci_language`               | string  | `""`    | `node`, `python` or `java`. Required when `run_ci` is true.        |
| `codeartifact_domain`       | string  | `""`    | CodeArtifact domain for private dependencies.                      |
| `codeartifact_repository`   | string  | `""`    | CodeArtifact repository.                                           |
| `codeartifact_domain_owner` | string  | `""`    | AWS account id owning the domain. Defaults to the calling account. |
| `codeartifact_namespace`    | string  | `""`    | npm scope bound to CodeArtifact, without the leading `@`.          |

**Container build** — `ec2`, `eks`, `lambda`

| Input        | Type   | Default       | Description                                                                                 |
| ------------ | ------ | ------------- | ------------------------------------------------------------------------------------------- |
| `dockerfile` | string | `Dockerfile`  | Dockerfile path, relative to `app_path`.                                                    |
| `build_args` | string | `""`          | Extra build arguments, one `KEY=value` per line. `ENV` and `APP_VERSION` are always passed. |
| `platforms`  | string | `linux/amd64` | `eks`, `lambda` only. Must match the Lambda function's architecture.                        |

**Target: `ec2`**

| Input               | Type   | Default              | Description                                                                           |
| ------------------- | ------ | -------------------- | ------------------------------------------------------------------------------------- |
| `docker_image_name` | string | `""`                 | **Required for `ec2`.** Image name, also the working directory on the instance.       |
| `s3_path`           | string | `""`                 | **Required for `ec2`.** S3 key prefix for the image tarball.                          |
| `port_mapping`      | string | `""`                 | Host-to-container mapping, e.g. `8080:8080`. Defaults to the `PORT_MAPPING` variable. |
| `compose_file`      | string | `docker-compose.yml` | Compose file path, relative to `app_path`.                                            |
| `health_check_url`  | string | `""`                 | Curled on the instance after start-up. Empty skips the check.                         |
| `secrets_region`    | string | `""`                 | Region holding the Secrets Manager secret, when it differs from the workload region.  |

**Target: `eks`**

| Input                  | Type   | Default   | Description                                                     |
| ---------------------- | ------ | --------- | --------------------------------------------------------------- |
| `ecr_repository`       | string | `""`      | **Required for `eks`.** ECR repository name.                    |
| `cluster_name`         | string | `""`      | **Required for `eks`.** EKS cluster name.                       |
| `namespace`            | string | `default` | Kubernetes namespace.                                           |
| `deploy_method`        | string | `kubectl` | `kubectl`, `kustomize` or `helm`.                               |
| `deployment_name`      | string | `""`      | Deployment to update. Required for `kubectl`.                   |
| `container_name`       | string | `""`      | Container inside the Deployment. Defaults to `deployment_name`. |
| `manifest_path`        | string | `""`      | Kustomize overlay directory. Required for `kustomize`.          |
| `kustomize_image_name` | string | `""`      | Image name in the manifests that kustomize rewrites.            |
| `helm_chart_path`      | string | `""`      | Chart directory or reference. Required for `helm`.              |
| `helm_release_name`    | string | `""`      | Helm release name. Required for `helm`.                         |
| `helm_values_file`     | string | `""`      | Values file passed to helm with `-f`.                           |
| `rollout_timeout`      | string | `10m`     | How long to wait for the rollout to become ready.               |

**Target: `lambda`**

| Input            | Type   | Default | Description                                                                                                 |
| ---------------- | ------ | ------- | ----------------------------------------------------------------------------------------------------------- |
| `function_name`  | string | `""`    | **Required for `lambda`.** Function name or ARN.                                                            |
| `ecr_repository` | string | `""`    | **Required for `lambda`.** ECR repository name.                                                             |
| `alias`          | string | `""`    | Alias moved to the new version, e.g. `live`. Empty skips alias management — and gives up one-step rollback. |

**Target: `static`**

| Input                | Type    | Default | Description                                                                                   |
| -------------------- | ------- | ------- | --------------------------------------------------------------------------------------------- |
| `build_output`       | string  | `dist`  | Build output directory, relative to `app_path`.                                               |
| `build_script`       | string  | `""`    | npm script for the build. Defaults to `build:<environment>` when it exists, else `build`.     |
| `run_test`           | boolean | `true`  | Run tests before deploying.                                                                   |
| `bucket`             | string  | `""`    | Destination bucket. Defaults to the `STATIC_SITE_BUCKET` variable.                            |
| `destination_prefix` | string  | `""`    | Key prefix inside the bucket.                                                                 |
| `distribution_id`    | string  | `""`    | CloudFront distribution to invalidate. Defaults to the `CLOUDFRONT_DISTRIBUTION_ID` variable. |

**Node** — `ci_language: node` and the `static` target

| Input             | Type   | Default      | Description                                                                                                                      |
| ----------------- | ------ | ------------ | -------------------------------------------------------------------------------------------------------------------------------- |
| `framework`       | string | `node`       | `node`, `nestjs`, `angular`, `react` or `nx`. Selects default scripts; `angular` adds `--watch=false --browsers=ChromeHeadless`. |
| `node_versions`   | string | `'["20.x"]'` | JSON array. The first entry is used for the `static` build.                                                                      |
| `package_manager` | string | `npm`        | `npm`, `yarn` or `pnpm`.                                                                                                         |

**Python** — `ci_language: python`

| Input             | Type   | Default        | Description                             |
| ----------------- | ------ | -------------- | --------------------------------------- |
| `python_versions` | string | `'["3.12"]'`   | JSON array of versions to test against. |
| `python_extras`   | string | `dev`          | Optional dependency group to install.   |
| `lint_command`    | string | `ruff check .` | Lint command.                           |
| `test_command`    | string | `pytest -q`    | Test command.                           |

**Java** — `ci_language: java`

| Input               | Type   | Default    | Description                                            |
| ------------------- | ------ | ---------- | ------------------------------------------------------ |
| `java_versions`     | string | `'["21"]'` | JSON array of JDK versions to test against.            |
| `java_distribution` | string | `temurin`  | JDK distribution, as accepted by `actions/setup-java`. |
| `build_tool`        | string | `maven`    | `maven` or `gradle`.                                   |

**Secrets**

| Secret            | Required | Needed for                                |
| ----------------- | -------- | ----------------------------------------- |
| `IAM_ROLE_ARN`    | Yes      | Everything.                               |
| `EC2_INSTANCE_ID` | No       | `ec2`.                                    |
| `AWS_SECRETS_ARN` | No       | `ec2`, when the container needs a `.env`. |

**Outputs**

| Output             | Produced by  | Description                                                     |
| ------------------ | ------------ | --------------------------------------------------------------- |
| `version`          | `ec2`, `eks` | Version that was deployed.                                      |
| `image_uri`        | `eks`        | Image reference that was deployed.                              |
| `rollback_key`     | `ec2`        | S3 key of this build's archive. Pass to `rollback-ec2.yml`.     |
| `function_version` | `lambda`     | Published version. Pass to `rollback-lambda.yml`.               |
| `deployed`         | all          | `true` when a deployment ran, `false` when the run was CI only. |

</details>

<details>
<summary><b><code>publish.yml</code> — all inputs, secrets and outputs</b></summary>

Only `ecosystem`, `codeartifact_domain` and `codeartifact_repository` are
required.

| Input                       | Type    | Default        | Description                                                                                                                                                 |
| --------------------------- | ------- | -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `ecosystem`                 | string  | —              | **Required.** `npm`, `pypi` or `maven`.                                                                                                                     |
| `codeartifact_domain`       | string  | —              | **Required.** CodeArtifact domain to publish into.                                                                                                          |
| `codeartifact_repository`   | string  | —              | **Required.** CodeArtifact repository to publish into.                                                                                                      |
| `mode`                      | string  | `auto`         | `auto`, `verify`, `snapshot` or `release`. `auto` picks release on a tag, verify on a pull request, snapshot otherwise.                                     |
| `app_path`                  | string  | `.`            | Package directory, relative to the repository root.                                                                                                         |
| `run_ci`                    | boolean | `true`         | Lint, test and build before publishing.                                                                                                                     |
| `aws_region`                | string  | `""`           | Region of the CodeArtifact domain. Set this — CI jobs have no environment to read `AWS_REGION` from.                                                        |
| `codeartifact_domain_owner` | string  | `""`           | AWS account id owning the domain.                                                                                                                           |
| `codeartifact_namespace`    | string  | `""`           | npm only. Scope bound to CodeArtifact, without the leading `@`.                                                                                             |
| `release_environment`       | string  | `prod`         | Environment used for a release. Protect this one with reviewers.                                                                                            |
| `snapshot_environment`      | string  | `dev`          | Environment used for snapshots and dry runs. For PyPI this name lands in the version, so it must be a PEP 440 pre-release segment: `dev`, `a`, `b` or `rc`. |
| `snapshot_version_strategy` | string  | `""`           | Overrides the snapshot strategy. Defaults to `manifest` for maven so a pom `-SNAPSHOT` survives, and `auto` elsewhere.                                      |
| `node_versions`             | string  | `'["20.x"]'`   | npm only. JSON array; the first entry publishes.                                                                                                            |
| `package_manager`           | string  | `npm`          | npm only. `npm`, `yarn` or `pnpm`.                                                                                                                          |
| `build_script`              | string  | `build`        | npm only. Script run before publishing. Empty publishes without building.                                                                                   |
| `npm_access`                | string  | `restricted`   | npm only. `restricted` or `public`.                                                                                                                         |
| `python_versions`           | string  | `'["3.12"]'`   | pypi only. JSON array; the first entry publishes.                                                                                                           |
| `python_extras`             | string  | `dev`          | pypi only. Optional dependency group installed for CI.                                                                                                      |
| `lint_command`              | string  | `ruff check .` | pypi only. Lint command.                                                                                                                                    |
| `test_command`              | string  | `pytest -q`    | pypi only. Test command.                                                                                                                                    |
| `java_versions`             | string  | `'["21"]'`     | maven only. JSON array; the first entry publishes.                                                                                                          |
| `java_distribution`         | string  | `temurin`      | maven only. JDK distribution.                                                                                                                               |
| `build_tool`                | string  | `maven`        | maven only. `maven` or `gradle`.                                                                                                                            |

**Secrets**: `IAM_ROLE_ARN` (required).

**Outputs**: `version` — the version published, empty when nothing was.
`mode` — the resolved mode: `verify`, `snapshot` or `release`.

## </details>

---

### Version strategies

`version_strategy` on `deploy.yml`, and the resolved strategy on `publish.yml`:

| Value        | Version                                                       | Use for            |
| ------------ | ------------------------------------------------------------- | ------------------ |
| `tag`        | The git tag, minus the leading `v`                            | Releases           |
| `auto`       | The tag when there is one, otherwise `<manifest>-<env>.<run>` | The default        |
| `manifest`   | Exactly what the manifest declares                            | Maven `-SNAPSHOT`  |
| `run-number` | `0.0.<run>`                                                   | Throwaway dry runs |

## Structure

Four layers. Entry points dispatch on one argument; pipelines chain stages;
stages own an environment and a runner; composite actions do one task inside
somebody else's job.

```
Entry points  deploy · publish
Pipelines     pipeline-ec2 · pipeline-eks · pipeline-lambda · pipeline-static
Stages        ci-* · build-* · publish-* · deploy-* · rollback-*
Actions       actions/aws-oidc-auth · actions/ssm-exec · actions/docker-build · …
```

Everything below the entry points stays public and composable, for the cases the
`target` and `ecosystem` arguments do not cover. Full reasoning in
[docs/architecture.md](docs/architecture.md).

---

## Pipelines

What the entry points dispatch to. Call one directly to skip the dispatch layer,
or when wrapping this repository in a reusable workflow of your own.

| Workflow                                                       | Does                                                         |
| -------------------------------------------------------------- | ------------------------------------------------------------ |
| [`pipeline-ec2.yml`](.github/workflows/pipeline-ec2.yml)       | Build → S3 → load onto EC2 over SSM → start with Compose     |
| [`pipeline-eks.yml`](.github/workflows/pipeline-eks.yml)       | Build → ECR → roll out to EKS via kubectl, kustomize or Helm |
| [`pipeline-lambda.yml`](.github/workflows/pipeline-lambda.yml) | Build → ECR → update the function → move the alias           |
| [`pipeline-static.yml`](.github/workflows/pipeline-static.yml) | Build → S3 sync → CloudFront invalidation                    |

## Stages

Compose these yourself when a pipeline does not fit.

**Build and test**

| Workflow                                           | Covers                                                                              |
| -------------------------------------------------- | ----------------------------------------------------------------------------------- |
| [`ci-node.yml`](.github/workflows/ci-node.yml)     | Node.js, NestJS, Angular, React, Nx. Version matrix, `nx affected`, artifact upload |
| [`ci-java.yml`](.github/workflows/ci-java.yml)     | Maven and Gradle. JDK matrix, test reports                                          |
| [`ci-python.yml`](.github/workflows/ci-python.yml) | Version matrix, ruff and pytest by default, optional sdist/wheel                    |

**Package**

| Workflow                                                         | Produces                                              |
| ---------------------------------------------------------------- | ----------------------------------------------------- |
| [`build-docker-ecr.yml`](.github/workflows/build-docker-ecr.yml) | Image in ECR, tagged by version, SHA and `latest`     |
| [`build-docker-s3.yml`](.github/workflows/build-docker-s3.yml)   | Image tarball in S3, both moving and immutable copies |

**Publish**

Library repository examples: [examples/publishing/](examples/publishing/).

| Workflow                                                   | Target             |
| ---------------------------------------------------------- | ------------------ |
| [`publish-npm.yml`](.github/workflows/publish-npm.yml)     | CodeArtifact npm   |
| [`publish-pypi.yml`](.github/workflows/publish-pypi.yml)   | CodeArtifact PyPI  |
| [`publish-maven.yml`](.github/workflows/publish-maven.yml) | CodeArtifact Maven |

**Deploy**

| Workflow                                                                             | Target                                                     |
| ------------------------------------------------------------------------------------ | ---------------------------------------------------------- |
| [`deploy-ec2-load-docker.yml`](.github/workflows/deploy-ec2-load-docker.yml)         | Pull the tarball from S3 onto the instance and load it     |
| [`deploy-ec2-start-container.yml`](.github/workflows/deploy-ec2-start-container.yml) | Write config, restart the container, optional health check |
| [`deploy-eks.yml`](.github/workflows/deploy-eks.yml)                                 | EKS, with rollout wait and failure diagnostics             |
| [`deploy-lambda.yml`](.github/workflows/deploy-lambda.yml)                           | Lambda, zip or container image, with alias management      |
| [`deploy-s3-cloudfront.yml`](.github/workflows/deploy-s3-cloudfront.yml)             | Static site, with correct cache headers per file type      |

**Roll back**

| Workflow                                                       | Mechanism                                |
| -------------------------------------------------------------- | ---------------------------------------- |
| [`rollback-ec2.yml`](.github/workflows/rollback-ec2.yml)       | Restore an archived image by version     |
| [`rollback-eks.yml`](.github/workflows/rollback-eks.yml)       | `rollout undo`, or pin an explicit image |
| [`rollback-lambda.yml`](.github/workflows/rollback-lambda.yml) | Repoint the alias at an earlier version  |

## Composite actions

Usable directly from any job:

```yaml
- uses: Ennovative-Genix/sgx-github-actions/actions/aws-oidc-auth@v1
  with:
    role-arn: ${{ secrets.IAM_ROLE_ARN }}
    fallback-region: ${{ vars.AWS_REGION }}
```

| Action                                                       | Does                                                                    |
| ------------------------------------------------------------ | ----------------------------------------------------------------------- |
| [`actions/aws-oidc-auth`](actions/aws-oidc-auth)             | Resolve the region and assume a role via OIDC. No stored keys           |
| [`actions/ssm-exec`](actions/ssm-exec)                       | Run commands on an instance over SSM and wait, with `jq`-built payloads |
| [`actions/docker-build`](actions/docker-build)               | Buildx with a per-image GHA layer cache; load locally or push           |
| [`actions/ecr-login`](actions/ecr-login)                     | Authenticate Docker to ECR, optionally creating the repository          |
| [`actions/s3-image-upload`](actions/s3-image-upload)         | `docker save` to S3, immutable copy first                               |
| [`actions/compute-version`](actions/compute-version)         | One version per run, from tag, manifest or run number                   |
| [`actions/codeartifact-login`](actions/codeartifact-login)   | Configure npm, pip, twine, Maven or Gradle against CodeArtifact         |
| [`actions/setup-node`](actions/setup-node)                   | Node with npm/yarn/pnpm caching and a lockfile-faithful install         |
| [`actions/setup-python`](actions/setup-python)               | Python with pip caching, requirements or pyproject                      |
| [`actions/setup-java`](actions/setup-java)                   | JDK with Maven/Gradle caching and a generated `settings.xml`            |
| [`actions/runner-disk-cleanup`](actions/runner-disk-cleanup) | Reclaim runner disk **inside** the job that needs it                    |

---

## Configuration

Set per GitHub Environment, not per repository — that is what makes `dev` and
`prod` differ without any branching in the workflow.

| Variable                                           | Needed for                                                        |
| -------------------------------------------------- | ----------------------------------------------------------------- |
| `AWS_REGION`                                       | Everything. Deployments fail fast without it rather than guessing |
| `S3_BUILD_BUCKET`                                  | EC2 path                                                          |
| `PORT_MAPPING`                                     | EC2 path                                                          |
| `CLOUDWATCH_LOG_GROUP`, `CLOUDWATCH_LOG_STREAM`    | EC2 path, optional                                                |
| `STATIC_SITE_BUCKET`, `CLOUDFRONT_DISTRIBUTION_ID` | Static path                                                       |

| Secret            | Needed for                                  |
| ----------------- | ------------------------------------------- |
| `IAM_ROLE_ARN`    | Everything                                  |
| `EC2_INSTANCE_ID` | EC2 path                                    |
| `AWS_SECRETS_ARN` | EC2 path, when the container needs a `.env` |

Full setup, including the IAM trust policy: [docs/onboarding.md](docs/onboarding.md).

## Versioning

Pin to `@v1`. It moves forward within the major line, so fixes arrive
automatically and breaking changes cannot.

| Ref       | Moves                 | Use for                                       |
| --------- | --------------------- | --------------------------------------------- |
| `@v1`     | Within the major line | **Default**                                   |
| `@v1.4.2` | Never                 | Production-critical or regulated repositories |
| `@main`   | Every merge           | This repository's own testing only            |

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

| Document                                      | Answers                                                    |
| --------------------------------------------- | ---------------------------------------------------------- |
| [architecture.md](docs/architecture.md)       | How it fits together, and why                              |
| [conventions.md](docs/conventions.md)         | Naming, branching, versioning, coding standards            |
| [contracts.md](docs/contracts.md)             | Designing inputs, outputs, secrets, permissions            |
| [decision-matrix.md](docs/decision-matrix.md) | Reusable workflow, composite action, or JavaScript action? |
| [onboarding.md](docs/onboarding.md)           | Wiring up a new repository                                 |
| [pitfalls.md](docs/pitfalls.md)               | Anti-patterns to avoid                                     |
| [examples/](examples/)                        | Working files to copy                                      |

---

Maintained by Platform Engineering · Navdeep Singh <navdeep.singh@solugenix.com>
