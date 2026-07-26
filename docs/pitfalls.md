# Pitfalls and anti-patterns

Each of these looks reasonable in review and fails in a way that is hard to trace
back. The design of this repository assumes them; reintroducing one usually means
undoing a deliberate decision.

## Cleanup in its own job

A `needs:` dependency that frees disk, prunes Docker and prints an encouraging
`df -h` before the build looks like a sensible stage. It does nothing at all:
every job gets a fresh runner, so it cleans a machine the build never sees.

Anything that manipulates runner state — disk, caches, installed tools,
environment variables — must be a **step inside the job that benefits**. That is
what `actions/runner-disk-cleanup` is for, and why it is an action rather than a
workflow.

**Rule:** if it changes the machine, it cannot be its own job.

## Building shell commands by string concatenation

Assembling an SSM payload by hand is the standard way to reach this failure:

```bash
COMMAND="echo $ENV_CONTENT | base64 -d > /var/tmp/app/.env"
aws ssm send-command --parameters "{\"commands\":[\"$COMMAND\"]}"
```

Three layers of quoting — YAML, shell, JSON — with nothing checking any of them.
A payload containing a quote, a backslash or a newline produces either a JSON
parse error or, worse, a valid document that runs something unintended.

`actions/ssm-exec` builds the payload with `jq`, which cannot produce invalid
JSON:

```bash
jq -n --arg commands "$SSM_COMMANDS" '{commands: ($commands | split("\n"))}'
```

**Rule:** structured data gets built by a tool that understands the structure.

## Interpolating `${{ }}` into a shell script body

```yaml
# A branch named  x`whoami`  executes whoami on the runner
run: echo "Deploying ${{ github.head_ref }}"
```

GitHub substitutes expressions textually before bash ever sees the script, so the
value becomes *code*. Pass through `env:` instead — bash then treats it as data:

```yaml
env:
  HEAD_REF: ${{ github.head_ref }}
run: echo "Deploying $HEAD_REF"
```

This matters most for anything a contributor controls: branch names, PR titles,
tag names, file contents.

## Deriving the region from the branch name

```yaml
AWS_REGION: ${{ startsWith(github.ref_name, 'release/') && 'us-east-1' || (github.ref_name == 'main') && 'us-east-1' || 'ap-south-1' }}
```

Expressions like this get copied into every workflow that needs a region and then
drift, so one file knows about a branch the others do not. Every new long-lived
branch means editing all of them, and the failure mode is silent: the build
succeeds, against the wrong account.

Configuration belongs in configuration. `vars.AWS_REGION` on the GitHub
Environment resolves it in one place, and the environment is already what decides
which account and which bucket to use. `actions/aws-oidc-auth` accepts no
fallback and fails when the region is unset, because a wrong region is much
harder to notice than a failed run.

**Rule:** if the same expression appears in three files, it is configuration.

## `secrets: inherit`

Convenient, and it hands the called workflow every secret the caller holds. When
the called workflow lives in another repository, that is a standing invitation.
Name each secret explicitly. It also documents, in the caller, exactly what the
workflow can reach.

## Pinning consumers to `@main`

Every merge to this repository immediately changes the behaviour of every
consumer pinned to `@main` — including production deployments, with no review of
their own. Consumers pin to `@v1`. `@main` is for this repository's own examples
and for deliberate canary testing.

## Unpinned third-party actions

`uses: some-org/some-action@master` runs whatever that repository contains at the
moment your job starts. Use a tag at minimum, and a commit SHA for anything that
touches credentials. Dependabot is configured here to keep those pins current, so
pinning does not mean going stale.

## `latest` as the only image tag

An image tagged only `latest` cannot be rolled back to, because there is no
earlier `latest`. `actions/compute-version` produces a version, a `sha-<short>`
tag and — for non-prereleases only — `latest`. `build-docker-s3.yml` writes both a
moving `latest.tar.gz` and an immutable `<version>.tar.gz`; `rollback-ec2.yml`
exists because of the second one.

## Rollback designed after the incident

A rollback path invented during an outage is a rollback path being tested in
production for the first time. The information rollback needs must be captured
during deployment:

- `build-docker-s3.yml` outputs `version_key`, the exact S3 object
- `deploy-lambda.yml` records `previous_version` **before** moving the alias
- `rollback-ec2.yml` verifies the archive exists *and* is in an immediately
  readable storage class before it touches the running instance

That last one matters: an object in `GLACIER` or `DEEP_ARCHIVE` needs an explicit
restore request that takes hours. Discovering this mid-incident, after the old
container has already been stopped, is the worst possible time.

## Forgetting that composite action inputs are strings

```yaml
inputs:
  push:
    default: "false"

# always true — "false" is a non-empty string
- if: inputs.push
```

`action.yml` has no boolean type. Compare explicitly: `if: inputs.push == 'true'`.

## Buildx provenance on images you intend to `docker save` or ship to Lambda

Recent Buildx versions attach provenance attestations by default, which turns the
result into a multi-platform manifest list. `docker save` and Lambda's container
support both expect a single image manifest and fail on the list. This repository
sets `provenance: false` in `actions/docker-build` for that reason. Turning it on
is reasonable for images destined only for a registry — just not for these two
paths.

## Matrix builds racing to upload the same artifact

`actions/upload-artifact@v4` errors when two jobs upload the same artifact name.
A three-version Node matrix will do exactly that. `ci-node.yml` suffixes the name
with the matrix value — `${{ inputs.artifact_name }}-node${{ matrix.node-version }}` —
which is also why `pipeline-static.yml` has to reconstruct the suffixed name when
it downloads.

## Nx `affected` on a shallow checkout

`actions/checkout` fetches depth 1 by default. `nx affected` compares against a
base ref that is not in the clone, and either fails or silently reports that
everything changed. `ci-node.yml` sets `fetch-depth: 0` when `nx_affected` is on,
and fetches the PR base branch explicitly.

## Silent success on an empty upload

`actions/upload-artifact` defaults to a warning when it finds no files, so a build
that produced nothing looks like a build that worked. Every upload here sets
`if-no-files-found: error`.

## Health checks that only check the port

Curling a port that is open proves Docker started a process. It does not prove
the application can reach its database. Point `health_check_url` at an endpoint
that exercises the dependencies you care about — and note that the check runs
*on the instance*, so it can use `localhost` and does not require the service to
be publicly reachable.
