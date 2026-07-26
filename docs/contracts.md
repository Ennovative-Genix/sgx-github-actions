# Inputs, outputs, secrets and permissions

The contract is the API. Consumers pin to `@v1` and expect it to hold.

## Inputs

**Required means unrecoverable.** An input is `required: true` only when no
sensible default exists and the workflow cannot proceed without it —
`docker_image_name`, `function_name`, `cluster_name`. Everything else takes a
default, because every required input is a question each new repository has to
answer before its first deployment.

**Defaults encode the common case.** `app_path` defaults to `.` because most
repositories are not monorepos. `platforms` defaults to `linux/amd64` because
most nodes are x86. A default that is wrong half the time is worse than no
default at all.

**Types are declared.** `type: boolean` and `type: number` in `workflow_call`
mean GitHub validates the value before the job starts. Composite actions get no
such luxury — `action.yml` supports only strings, so boolean-ish inputs are
documented as `"true"` / `"false"` and compared explicitly:

```yaml
- if: inputs.cache == 'true'      # `if: inputs.cache` is true for the string "false"
```

**Adding an input is a minor bump; changing one is a major bump.** A new input
with a default is backward compatible. Renaming one, or changing what a default
does, is not — consumers pinned at `@v1` must never see it.

**Deprecate before removing.** GitHub rejects a `with:` key the callee does not
declare, so deleting an input breaks every consumer still passing it — including
ones that pass it harmlessly. Stop using the input, mark the description
`Deprecated`, and leave the declaration in place until the next major version.

## Outputs

**Emit what the next stage needs, and what a human needs at 2am.**
`build-docker-s3.yml` returns `version` and `version_key` — the first so a
pipeline can label the deployment, the second so `rollback-ec2.yml` has an exact
S3 object to return to. `deploy-lambda.yml` returns `previous_version`, captured
*before* the alias moves, so a failed deployment still leaves a rollback target
behind.

Reusable workflow outputs must be plumbed through explicitly, twice:

```yaml
jobs:
  build:
    outputs:
      version: ${{ steps.version.outputs.version }}   # step -> job

on:
  workflow_call:
    outputs:
      version:
        value: ${{ jobs.build.outputs.version }}      # job -> workflow
```

Miss either hop and the output is silently empty. There is no error.

**Outputs from a skipped job are empty strings, not errors.** A downstream
`if:` that assumes a value will run with an empty one.

**Never output a secret.** Job and workflow outputs are not masked in the
consuming workflow. `actions/codeartifact-login` outputs a token and calls
`::add-mask::` on it first, but it is a *step* output inside one job, which is a
meaningfully smaller blast radius than a workflow output.

## Secrets

**Declare every secret; never rely on inheritance.** `secrets: inherit` hands the
called workflow every secret the caller has, including ones it has no business
seeing. Every workflow here names exactly what it needs:

```yaml
secrets:
  IAM_ROLE_ARN:
    description: "AWS IAM Role ARN for OIDC authentication."
    required: true
  AWS_SECRETS_ARN:
    description: "Secrets Manager ARN holding the .env contents."
    required: false
```

**Prefer a role ARN to a credential.** The only AWS secret in this repository is
an IAM role ARN — which is not really a secret at all, since it is useless
without a matching trust policy naming the repository. There are no access keys
anywhere. `actions/aws-oidc-auth` exchanges the GitHub OIDC token for STS
credentials scoped to a single run.

**Application secrets belong in Secrets Manager, not GitHub.** The `.env` a
container needs is fetched at deploy time from the ARN in `AWS_SECRETS_ARN`. This
keeps runtime configuration out of GitHub entirely, and means rotating a database
password does not involve a workflow run.

**Optional secrets are checked, not assumed.** `if: steps.files.outputs.has-env == 'true'`
rather than `if: secrets.AWS_SECRETS_ARN != ''` — the `secrets` context is not
available in every position, and an unset optional secret is an empty string that
happily produces a broken command.

## Permissions

**Every workflow declares its own.** The default is read-only at the top:

```yaml
permissions:
  contents: read
```

and jobs that need more opt in individually:

```yaml
jobs:
  deploy:
    permissions:
      id-token: write     # required to mint the OIDC token
      contents: read
```

`id-token: write` is what lets a job request a GitHub OIDC token. Without it,
`aws-actions/configure-aws-credentials` fails with an unhelpful error about
missing credentials. It is scoped per job so that a job which does not touch AWS
cannot mint a token at all.

**Permissions do not inherit into called workflows.** A job that calls a reusable
workflow must declare the permissions that workflow's jobs need — the callee
cannot grant itself more than the caller has. Every `pipeline-*.yml` job that
calls a deploy stage repeats `id-token: write`, and it is not redundant.

`release.yml` is the only workflow with `contents: write`, because moving the
floating `v1` tag means pushing to the repository.

## Environments

Deploy and publish stages declare `environment: ${{ inputs.environment }}`. That
single line is what makes GitHub's protection rules apply: required reviewers,
wait timers, and branch policies restricting which refs may deploy where.

It is also where per-environment configuration comes from. Variables resolve
against the job's environment, so `vars.S3_BUILD_BUCKET` is a different bucket in
`dev` and in `prod` with no branching in the workflow.

**CI stages deliberately have no environment.** `ci-node.yml` and friends run on
pull requests from forks and contributors; binding them to an environment would
either block them behind approval or expose environment secrets to untrusted
code.

## Region resolution

Two sources, most explicit first:

1. The `aws_region` workflow input, for the rare case where one environment spans
   regions.
2. `vars.AWS_REGION` on the job's GitHub Environment. **This is where it belongs.**

If neither resolves, the run **fails**. There is no default and no inference from
the branch name. A guessed region is a deployment that lands in the wrong account
while reporting success, which is strictly worse than a run that stops.

`deploy-ec2-start-container.yml` takes a separate optional `secrets_region`,
defaulting to the deployment region. Set it only when Secrets Manager secrets are
centralised somewhere other than where the workload runs.

## Checklist for a new stage

- [ ] Every input has a `description`, an explicit `required`, and a `default` unless genuinely required
- [ ] Booleans and numbers use `type:`, not `type: string`
- [ ] Secrets are named individually; no `secrets: inherit`
- [ ] `permissions` declared at workflow level, widened per job only where needed
- [ ] `id-token: write` on any job that touches AWS
- [ ] `environment:` set on anything that deploys or publishes
- [ ] Values reach `run:` through `env:`, not through `${{ }}` in the script body
- [ ] Outputs plumbed step → job → workflow
- [ ] Named in `README.md` or `docs/` — `validate.yml` enforces this
