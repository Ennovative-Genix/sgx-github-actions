# Conventions

## Repository layout

```
sgx-github-actions/
├── .github/
│   ├── workflows/           # Reusable workflows — MUST be flat, GitHub ignores subdirectories
│   ├── dependabot.yml
│   └── CODEOWNERS
├── actions/                 # Composite actions, one directory each
│   └── <action-name>/
│       ├── action.yml
│       └── *.sh             # Longer logic, kept out of YAML
├── docs/                    # This directory
├── examples/                # Copy-paste starting points, one per stack
├── scripts/                 # Repository maintenance, not used by consumers at runtime
└── .actionlint.yaml
```

`.github/workflows/` cannot be nested. GitHub only discovers workflow files at
the top level of that directory, so the folder hierarchy that would normally
express grouping has to live in the filename instead. Everything else in the
repository is free to nest, and `actions/` does.

## Workflow naming

`<layer>-<target>.yml`, all lowercase, hyphen-separated.

| Prefix | Layer | Meaning | Examples |
| --- | --- | --- | --- |
| `ci-` | stage | Lint, test, build source | `ci-node.yml`, `ci-java.yml`, `ci-python.yml` |
| `build-` | stage | Produce a deployable artifact | `build-docker-ecr.yml`, `build-docker-s3.yml` |
| `publish-` | stage | Push a package to a registry | `publish-npm.yml`, `publish-pypi.yml`, `publish-maven.yml` |
| `deploy-` | stage | Ship to one AWS service | `deploy-eks.yml`, `deploy-lambda.yml`, `deploy-s3-cloudfront.yml` |
| `rollback-` | stage | Undo a deployment | `rollback-ec2.yml`, `rollback-eks.yml`, `rollback-lambda.yml` |
| `pipeline-` | pipeline | Chain stages end to end for one target | `pipeline-ec2.yml`, `pipeline-eks.yml`, `pipeline-lambda.yml`, `pipeline-static.yml` |
| *(none)* | entry point | Dispatch to a pipeline on one argument | `deploy.yml`, `publish.yml` |

Entry points carry no prefix, deliberately: they are the front door, and the
unprefixed name is what a consumer types. There should be very few of them —
one per product shape, not one per technology. A third would need to justify
itself against adding a `target` value to `deploy.yml`.

The `name:` inside the file uses title case with a hyphen separator —
`name: Deploy - EKS` — because that string is what appears in the Actions UI and
in required-status-check configuration.

## Composite action naming

`<verb>-<noun>` or `<noun>-<noun>`, matching the directory name exactly:
`aws-oidc-auth`, `setup-node`, `docker-build`, `ssm-exec`, `compute-version`.

An action directory holds `action.yml` plus any scripts it needs. Logic longer
than roughly twenty lines moves into a `.sh` file next to `action.yml` and runs
via `bash "$GITHUB_ACTION_PATH/script.sh"` — shell embedded in YAML gets no
syntax checking, no shellcheck, and no way to run it locally.

## Input naming

Two different conventions, deliberately:

- **Reusable workflow inputs use `snake_case`** — `docker_image_name`, `app_path`.
- **Composite action inputs use `kebab-case`** — `image-name`, `role-arn`.

This matches what the surrounding ecosystem does (`actions/setup-node` takes
`node-version`; workflow inputs across GitHub's own examples are snake_case), and
the visual difference makes it immediately obvious which layer a call is
crossing.

## Branching

| Branch | Purpose | Protection |
| --- | --- | --- |
| `main` | Released, consumable state | Required review, required `Validate` check, linear history |
| `feat/<slug>` | New capability | — |
| `fix/<slug>` | Bug fix | — |
| `docs/<slug>` | Documentation only | — |

Work merges to `main` via pull request. `main` is never what production consumers
pin to — see below.

## Versioning

This repository is consumed by reference, so its version *is* its git ref.
Semantic versioning applies to the workflow contract:

- **Major** — a removed or renamed input, a new required input or secret, a
  changed default that alters behaviour, a removed workflow.
- **Minor** — a new optional input, a new workflow or action, a new output.
- **Patch** — a fix that leaves the contract unchanged.

Three kinds of ref exist:

| Ref | Moves? | Who uses it |
| --- | --- | --- |
| `v1.4.2` | Never | Regulated or production-critical repositories |
| `v1.4` | Within the minor line | Rare |
| `v1` | Within the major line | **The default. Most repositories pin here.** |
| `main` | Every merge | This repository's own examples, and nothing else |

`v1` is the recommendation: consumers get fixes and new optional inputs
automatically, and a breaking change can never reach them without an explicit
bump to `v2`.

### Cutting a release

```bash
git tag v1.4.2
git push origin v1.4.2
```

**Use a lightweight tag. Never `git tag -a`.** Workflows in this repository call
each other by relative path (`publish.yml` fans out to `./.github/workflows/publish-npm.yml`,
`pipeline-ec2.yml` to its stages, and so on). When a consumer pins to an
annotated tag, GitHub Actions resolves those relative paths against the tag
*object* SHA rather than the commit it points at, and the nested call fails at
parse time:

```
error parsing called workflow
".github/workflows/deploy.yml"
-> "Ennovative-Genix/sgx-github-actions/.github/workflows/publish.yml@v2.0.0" (source tag with sha:5fdacf41...)
--> "./.github/workflows/publish-npm.yml"
: workflow was not found.
```

The tag looks fine — the file is right there in the tree — and calling
`publish.yml` directly still works, so this only surfaces once a consumer
reaches a nested workflow. Recovering means deleting and republishing the tag,
which every pinned consumer sees. Tag lightweight the first time.

`release.yml` takes it from there: it validates the tag shape, runs
`scripts/check-internal-refs.sh`, force-moves `v1` and `v1.4` onto the commit, and
opens a GitHub Release with generated notes. Prereleases (`v1.5.0-rc.1`) are
published as releases but deliberately do **not** move the floating tags — a
release candidate must never reach consumers pinned at `v1`.

### Cutting a new major line

Internal composite-action references carry a hardcoded ref (see
[architecture.md](architecture.md#why-internal-references-are-fully-qualified)).
Before tagging `v2.0.0`:

```bash
scripts/pin-internal-refs.sh v2
scripts/check-internal-refs.sh
git commit -am "chore: pin internal action references to v2"
```

Skip this and `v2` workflows will keep calling `v1` actions — which works, right
up until the day the two contracts diverge.

## Environments

`dev`, `qa`, `uat`, `stg`, `prod` are GitHub Environments, configured per
application repository. Each carries its own variables, its own secrets and its
own protection rules.

The environment name is an input to every deploy stage, and every deploy job
declares `environment: ${{ inputs.environment }}`. That is what makes required
reviewers on `prod` actually block a deployment.

## Coding standards

**Shell.** Every `run:` block starts `set -euo pipefail`. Untrusted or
caller-supplied values reach the shell through `env:`, never through direct
`${{ }}` interpolation into the script body:

```yaml
# WRONG — a value containing a backtick or $(…) executes on the runner
run: echo "Deploying ${{ inputs.image_name }}"

# RIGHT
env:
  IMAGE_NAME: ${{ inputs.image_name }}
run: echo "Deploying $IMAGE_NAME"
```

**Every input is documented.** `description:` is mandatory and says what the
value does, not what it is named. `required:` and `default:` are always explicit.

**Comments explain the non-obvious.** A comment saying "checkout the repository"
above `actions/checkout` is noise. A comment saying why `provenance` defaults to
false — because attestations produce a manifest list that `docker save` rejects —
is the reason the next person does not undo the setting.

**Failures are actionable.** `::error title=…::` messages name the variable to
set or the command to run, because the person reading the log is usually not the
person who wrote the workflow.

## Documentation structure

| File | Answers |
| --- | --- |
| `README.md` | What exists, and how do I call it? |
| `docs/architecture.md` | How does it fit together, and why? |
| `docs/conventions.md` | What are the rules for adding to it? |
| `docs/contracts.md` | How do I design inputs, outputs, secrets, permissions? |
| `docs/decision-matrix.md` | Which mechanism should I use? |
| `docs/onboarding.md` | How do I wire up a new application repository? |
| `docs/pitfalls.md` | What should I avoid? |
| `examples/` | Show me a working file I can copy. |

`validate.yml` fails the build if a reusable workflow or composite action is not
mentioned in `README.md` or `docs/`. Undiscoverable shared code gets copy-pasted
instead of reused, which is exactly the outcome this repository exists to
prevent.
