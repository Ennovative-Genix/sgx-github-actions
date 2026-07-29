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
Actions       actions/aws-oidc-auth · actions/setup-node · actions/compute-version · actions/codeartifact-login
```

Everything below the entry point stays public and composable, for the cases
`publish.yml` does not cover. Full reasoning in
[docs/architecture.md](docs/architecture.md).

---

## Stages

Compose these yourself when the entry point does not fit.

| Workflow                                               | Does                                                                                |
| ------------------------------------------------------ | ----------------------------------------------------------------------------------- |
| [`ci-node.yml`](.github/workflows/ci-node.yml)         | Node.js, NestJS, Angular, React, Nx. Version matrix, `nx affected`, artifact upload |
| [`publish-npm.yml`](.github/workflows/publish-npm.yml) | Version, build and publish a package to CodeArtifact npm                            |

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
| [`actions/codeartifact-login`](actions/codeartifact-login) | Configure npm against CodeArtifact                              |

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

| Name                  | Passed as       | Holds                                                       |
| --------------------- | --------------- | ----------------------------------------------------------- |
| `codeartifact`        | BuildKit secret | The authorization token, at `/run/secrets/codeartifact`     |
| `codeartifact_token`  | BuildKit secret | The same token, at `/run/secrets/codeartifact_token`        |

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
