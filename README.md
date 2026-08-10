# sgx-github-actions

Centralised npm publishing for the organisation. Library repositories describe
_what_ they publish; this repository owns _how_ it happens.

```yaml
jobs:
  release:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/publish.yml@v1
    permissions:
      id-token: write
      contents: read
    with:
      aws_region: us-east-1
      codeartifact_domain: sgx
      codeartifact_repository: npm-store
      codeartifact_namespace: sgx
    secrets:
      IAM_ROLE_ARN: ${{ secrets.IAM_ROLE_ARN }}
```

That is the whole file. A pull request builds, tests and dry-runs the publish; a
push publishes a snapshot; a `v1.4.3` tag publishes the release. Start with
[docs/onboarding.md](docs/onboarding.md), then copy
[examples/publishing/release.yml](examples/publishing/release.yml).

---

## Entry point

Every library repository needs exactly this one, called once.

| Workflow                                       | For           | Reads                          |
| ---------------------------------------------- | ------------- | ------------------------------ |
| [`publish.yml`](.github/workflows/publish.yml) | npm libraries | The trigger, to resolve `mode` |

It reads the trigger to decide what to do — pull request verifies, push
publishes a snapshot, tag publishes a release — and prints the resolved plan to
the job summary. Override with the `mode` input.

## ❗All Inputs, Secrets and Outputs❗

<details>
<summary><b><code>publish.yml</code> — all inputs, secrets and outputs</b></summary>

Only `codeartifact_domain` and `codeartifact_repository` are required. Set
`aws_region` too unless every run has an environment to read it from — the CI job
does not.

| Input                       | Type    | Default      | Description                                                                                                                             |
| --------------------------- | ------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------- |
| `codeartifact_domain`       | string  | —            | **Required.** CodeArtifact domain to publish into.                                                                                      |
| `codeartifact_repository`   | string  | —            | **Required.** CodeArtifact repository to publish into.                                                                                  |
| `mode`                      | string  | `auto`       | `auto`, `verify`, `snapshot` or `release`. `auto` picks release on a tag, verify on a pull request, snapshot otherwise.                 |
| `app_path`                  | string  | `.`          | Package directory, relative to the repository root.                                                                                     |
| `run_ci`                    | boolean | `true`       | Lint, test and build before publishing.                                                                                                 |
| `aws_region`                | string  | `""`         | Region of the CodeArtifact domain. Set this — CI jobs have no environment to read `AWS_REGION` from.                                    |
| `codeartifact_domain_owner` | string  | `""`         | AWS account id owning the domain. Defaults to the calling account.                                                                      |
| `codeartifact_namespace`    | string  | `""`         | npm scope bound to CodeArtifact, without the leading `@`. Empty binds the default registry.                                             |
| `release_environment`       | string  | `prod`       | Environment used for a release. Protect this one with reviewers.                                                                        |
| `snapshot_environment`      | string  | `dev`        | Environment used for snapshots and dry runs. Its name lands in the prerelease version, e.g. `1.4.2-dev.87`.                             |
| `snapshot_version_strategy` | string  | `""`         | Overrides the snapshot strategy: `auto`, `manifest` or `run-number`. Empty means `auto`.                                                |
| `node_versions`             | string  | `'["20.x"]'` | JSON array of Node versions to test against; the first publishes.                                                                       |
| `package_manager`           | string  | `npm`        | `npm`, `yarn` or `pnpm`.                                                                                                                |
| `build_script`              | string  | `build`      | Script run before publishing. Empty publishes without building.                                                                         |
| `npm_access`                | string  | `restricted` | `restricted` or `public`. Applies to scoped packages only; npm rejects the flag on an unscoped one, so it is omitted with a log notice. |

**Secrets**

| Secret         | Required | Needed for  |
| -------------- | -------- | ----------- |
| `IAM_ROLE_ARN` | Yes      | Everything. |

**Outputs**

| Output    | Description                                           |
| --------- | ----------------------------------------------------- |
| `version` | The version published, empty when nothing was.        |
| `mode`    | The resolved mode: `verify`, `snapshot` or `release`. |

</details>

---

### Version strategies

The resolved strategy on `publish.yml`, and the `version_strategy` input on
`publish-npm.yml`:

| Value        | Version                                                       | Use for                |
| ------------ | ------------------------------------------------------------- | ---------------------- |
| `tag`        | The git tag, minus the leading `v`                            | Releases               |
| `auto`       | The tag when there is one, otherwise `<manifest>-<env>.<run>` | The default            |
| `manifest`   | Exactly what `package.json` declares                          | Manual version control |
| `run-number` | `0.0.<run>`                                                   | Throwaway dry runs     |

## Structure

Three layers. The entry point resolves a plan; stages own an environment and a
runner; composite actions do one task inside somebody else's job.

```
Entry point   publish
Stages        ci-node · publish-npm
Actions       actions/aws-oidc-auth · actions/setup-node · actions/compute-version · actions/codeartifact-token
```

Everything below the entry point stays public and composable, for the cases
`publish.yml` does not cover. Full reasoning in
[docs/architecture.md](docs/architecture.md).

---

## Stages

Compose these yourself when the entry point does not fit.

| Workflow                                                 | Does                                                                                |
| -------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| [`ci-node.yml`](.github/workflows/ci-node.yml)           | Node.js, NestJS, Angular, React, Nx. Version matrix, `nx affected`, artifact upload |
| [`publish-npm.yml`](.github/workflows/publish-npm.yml)   | Version, build and publish a package to CodeArtifact npm                            |
| [`publish-pypi.yml`](.github/workflows/publish-pypi.yml) | Version, build and publish a package to CodeArtifact PyPI                           |

Library repository example: [examples/publishing/](examples/publishing/).

## Composite actions

Usable directly from any job:

```yaml
- uses: Ennovative-Genix/sgx-github-actions/actions/aws-oidc-auth@v1
  with:
    role-arn: ${{ secrets.IAM_ROLE_ARN }}
    fallback-region: ${{ vars.AWS_REGION }}
```

| Action                                                     | Does                                                            |
| ---------------------------------------------------------- | --------------------------------------------------------------- |
| [`actions/aws-oidc-auth`](actions/aws-oidc-auth)           | Resolve the region and assume a role via OIDC. No stored keys   |
| [`actions/setup-node`](actions/setup-node)                 | Node with npm/yarn/pnpm caching and a lockfile-faithful install |
| [`actions/compute-version`](actions/compute-version)       | One version per run, from tag, manifest or run number           |
| [`actions/codeartifact-token`](actions/codeartifact-token) | Mint a CodeArtifact token; configure npm, pip or twine with it  |

---

## Lambda

**The project owns building and zipping.** This workflow installs the toolchain,
runs the project's own build and zip entry points, uploads the zip straight to
Lambda and publishes an immutable version. There is no S3 hop.

```yaml
jobs:
  deploy:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/deploy-lambda.yml@development
    permissions:
      id-token: write
      contents: read
    with:
      environment: dev
      function_name: my-fn-dev
      runtime: nodejs
      app_path: services/my-fn
      # npm run build, then npm run zip — these are the defaults
    secrets:
      IAM_ROLE_ARN: ${{ secrets.IAM_ROLE_ARN }}
```

`environment` binds the approval rules and supplies `AWS_REGION`, exactly as the
EC2 flow does.

### Build and zip entry points

| `runtime` | Build                        | Zip                        | Toolchain installed           |
| --------- | ---------------------------- | -------------------------- | ----------------------------- |
| `nodejs`  | `npm run <npm_build_script>` | `npm run <npm_zip_script>` | Node + `npm ci` in `app_path` |
| `python`  | `<build_script>`             | `<zip_script>`             | Python + `uv` (or `pip`)      |

**The zip entry point is always optional.** Leave it empty and that step is
skipped, on the assumption that the build entry point already produced the zip.
Only the build entry point is mandatory: `npm_build_script` defaults to `build`,
and `build_script` is **required** when `runtime` is `python`.

For `nodejs` the scripts default to `build` and `zip`, so a conforming project
passes neither.

For `python`, `build_script` and `zip_script` are paths relative to `app_path`.
They run directly when executable (so a shebang'd `.py` works) and under `bash`
otherwise. Both are checked for existence up front:

```yaml
with:
  environment: dev
  function_name: my-fn-dev
  runtime: python
  app_path: services/my-fn
  build_script: scripts/build.sh
  zip_script: scripts/package.sh # omit when build.sh zips too
  python_package_manager: uv # or pip
```

`build_script` also owns installing the project's dependencies — the workflow
only puts the interpreter and `uv` on the runner. Linting and testing belong in
the project's own CI, not here; this workflow builds, zips and deploys.

### Finding the zip

`artifact_path` names the produced zip, relative to `app_path`. Leave it empty
and the workflow searches `app_path` three levels deep — skipping `node_modules`,
`.git`, `.venv` and `venv` — and requires exactly one match. Zero matches or
several is a failure that names the problem, not a guess.

Uploading the zip in the API request caps it at **50 MiB**. The workflow checks
the size before calling AWS so an oversized package fails with that number
rather than a bare `RequestEntityTooLarge`.

### Versions and rollback

Only the code is updated. The function's own configuration — architecture,
memory, timeout, handler, environment variables — is left untouched, so whatever
manages that configuration stays the single source of truth for it.

A numbered version is published on every run, and only **after** the code update
reaches `LastUpdateStatus: Successful` — a failed update never leaves a version
pointing at code that did not come up. `--code-sha256` makes the publish a
compare-and-swap, so two runs racing cannot publish each other's code.

Every version is immutable, so rolling back needs no rebuild. Take the
`function_version` output of the run you want back and point at it directly, or
put an alias on it:

```bash
aws lambda update-alias --function-name my-fn-dev --name live --function-version 42
```

<details>
<summary><b><code>deploy-lambda.yml</code> — all inputs, secrets and outputs</b></summary>

| Input                    | Type   | Default | Description                                                                                |
| ------------------------ | ------ | ------- | ------------------------------------------------------------------------------------------ |
| `environment`            | string | —       | **Required.** Target environment. Supplies `AWS_REGION`.                                   |
| `function_name`          | string | —       | **Required.** Name of the function to update.                                              |
| `runtime`                | string | —       | **Required.** `nodejs` or `python`.                                                        |
| `app_path`               | string | `.`     | Directory the entry points run in. Script paths resolve from here.                         |
| `artifact_path`          | string | `""`    | Path to the produced zip, relative to `app_path`. Empty auto-discovers exactly one `.zip`. |
| `npm_build_script`       | string | `build` | npm script that builds. Empty skips the build. `nodejs` only.                              |
| `npm_zip_script`         | string | `zip`   | npm script that zips. Empty means the build script already zips. `nodejs` only.            |
| `build_script`           | string | `""`    | Path to the build script, relative to `app_path`. **Required** when `runtime` is `python`. |
| `zip_script`             | string | `""`    | Path to the zip script, relative to `app_path`. Empty means `build_script` already zips.   |
| `python_package_manager` | string | `uv`    | `uv` or `pip`. Installed before `build_script` runs; the script decides how to use it.     |
| `node_version`           | string | `24.x`  | Node version installed for the `nodejs` path.                                              |
| `python_version`         | string | `3.12`  | Python version installed for the `python` path. Match the function's runtime.              |
| `aws_region`             | string | `""`    | Region of the function. Empty falls back to the environment's `AWS_REGION`.                |

**Secrets**

| Secret         | Required | Needed for  |
| -------------- | -------- | ----------- |
| `IAM_ROLE_ARN` | Yes      | Everything. |

**Outputs**

| Output             | Description                                                               |
| ------------------ | ------------------------------------------------------------------------- |
| `function_version` | Immutable numbered version published from this run.                       |
| `code_sha256`      | `CodeSha256` of the deployed package. Identifies the exact bytes running. |

</details>

The role in `IAM_ROLE_ARN` needs exactly three permissions on the function:
`lambda:UpdateFunctionCode`, `lambda:GetFunctionConfiguration` and
`lambda:PublishVersion`. Because the zip travels in the request, no S3
permissions and no build bucket are involved.

---

## CodeArtifact inside a Docker build

`npm ci` inside a `docker build` runs in a container with no AWS credentials, so
a private CodeArtifact registry fails there even when the runner is authenticated.
Set `codeartifact_domain` on `deploy-init.yml` and the build mints a token before
the image is built and hands it to BuildKit:

```yaml
jobs:
  deploy:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/deploy-init.yml@development
    with:
      environment: dev
      docker_image_name: my-api
      s3_path: my-api/dev
      codeartifact_domain: sgx
      codeartifact_domain_owner: "123456789012" # optional, defaults to the calling account
      codeartifact_region: us-east-1 # where the domain lives, not where you deploy
    secrets:
      IAM_ROLE_ARN: ${{ secrets.IAM_ROLE_ARN }}
      EC2_INSTANCE_ID: ${{ secrets.EC2_INSTANCE_ID }}
```

Leaving `codeartifact_domain` empty skips the whole thing, so existing callers
build exactly as before.

The build then reaches the `Dockerfile` as one BuildKit secret, exposed under two
ids so either naming convention works:

| Name                 | Passed as       | Holds                                                   |
| -------------------- | --------------- | ------------------------------------------------------- |
| `codeartifact`       | BuildKit secret | The authorization token, at `/run/secrets/codeartifact` |
| `codeartifact_token` | BuildKit secret | The same token, at `/run/secrets/codeartifact_token`    |

The registry endpoint and scope are **not** passed — the `Dockerfile` and the
repository's own `.npmrc` own those. Only the token comes from the workflow.

The token is a **secret mount, not a build arg**, because build args are recorded
in the image history — and this image is pushed to S3 and unpacked on EC2, where
`docker history` would read it straight back. Read it inside the `RUN` that needs
it so it never reaches a layer:

```dockerfile
# syntax=docker/dockerfile:1.7
FROM node:24-slim AS build

WORKDIR /app
COPY package*.json .npmrc ./

RUN --mount=type=secret,id=codeartifact,required=true \
    CODEARTIFACT_AUTH_TOKEN="$(cat /run/secrets/codeartifact)" npm ci
```

Prefer `required=true`. With `required=false` a missing secret produces an empty
token and the build dies later at `npm ci` with an opaque `E401`, rather than
saying the secret never arrived.

The IAM role in `IAM_ROLE_ARN` needs `codeartifact:GetAuthorizationToken`,
`codeartifact:GetRepositoryEndpoint`, `codeartifact:ReadFromRepository` and
`sts:GetServiceBearerToken`.

---

## Configuration

Set per GitHub Environment, not per repository — that is what makes `dev` and
`prod` differ without any branching in the workflow.

| Variable     | Needed for                                                                        |
| ------------ | --------------------------------------------------------------------------------- |
| `AWS_REGION` | The publish job. The CI job has no environment, so pass `aws_region` for that one |

| Secret         | Needed for |
| -------------- | ---------- |
| `IAM_ROLE_ARN` | Everything |

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
- **The CodeArtifact token is masked** the moment it is minted, and never leaves the job that requested it
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
