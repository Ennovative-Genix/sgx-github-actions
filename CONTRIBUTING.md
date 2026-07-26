# Contributing

Changes here reach every application repository in the organisation. A broken
workflow on `main` is a broken deployment everywhere the next time someone
merges.

## Before you start

Read [docs/decision-matrix.md](docs/decision-matrix.md) and decide what you are
building:

- Needs its own environment, approval gate, matrix, or runner → **reusable workflow** in `.github/workflows/`
- Runs inside somebody else's job → **composite action** in `actions/`

Prefer extending an existing entry point to adding a new one. A new deployment
target is a `target` value in `deploy.yml` plus a `pipeline-*` workflow; a new
package format is an `ecosystem` value in `publish.yml` plus a `publish-*`
workflow. A third entry point needs to justify why it is not one of those.

Nothing new can be inserted *between* an entry point and a stage — that chain is
already at GitHub's four-level nesting limit, and `scripts/check-nesting-depth.py`
fails the build if it grows.

## Rules

Full detail in [docs/conventions.md](docs/conventions.md) and
[docs/contracts.md](docs/contracts.md). The ones most often missed:

1. **`.github/workflows/` is flat.** GitHub ignores subdirectories there. Grouping lives in the filename prefix.
2. **Reference internal actions by full path**, never `./actions/…`:
   ```yaml
   uses: Ennovative-Genix/sgx-github-actions/actions/aws-oidc-auth@main
   ```
   At step level, `./` resolves against the *consumer's* checkout.
3. **Every `run:` starts `set -euo pipefail`.**
4. **Caller values reach the shell through `env:`**, not `${{ }}` in the script body.
5. **Every input has a `description`, explicit `required`, and a `default`** unless genuinely mandatory.
6. **Name secrets individually.** No `secrets: inherit`.
7. **`permissions: contents: read`** at workflow level; widen per job only where needed. `id-token: write` on anything touching AWS.
8. **Document it.** `validate.yml` fails if a workflow or action is not mentioned in `README.md` or `docs/`.

## Local checks

```bash
# Contracts and references
scripts/check-internal-refs.sh

# Everything CI runs, if you have the tools
actionlint
find . -name '*.sh' -not -path './.git/*' | xargs shellcheck
```

## Changing an existing contract

| Change | Version impact | Allowed on the current major? |
| --- | --- | --- |
| New optional input, workflow, action, output | minor | Yes |
| Bug fix, no contract change | patch | Yes |
| New required input or secret | major | No |
| Renamed or removed input | major | No |
| Changed default that alters behaviour | major | No |

To retire an input without a major bump: stop using it, prefix its description
with `Deprecated`, and leave the declaration in place until the next major
version. Removing it outright breaks every consumer still passing it, because
GitHub rejects a `with:` key the callee does not declare.

## Testing a change

Composite actions and workflows cannot be fully tested in isolation. Push a
branch and point a real repository at it:

```yaml
uses: Ennovative-Genix/sgx-github-actions/.github/workflows/pipeline-ec2.yml@feat/my-change
```

Deploy to `dev`. For anything touching the deploy or rollback path, exercise the
rollback too — that path is only ever used under pressure, so it has to be
verified when there is none.

## Releasing

```bash
git tag v1.4.2
git push origin v1.4.2
```

Lightweight, not `git tag -a`. Annotated tags break consumers — see
[conventions.md](docs/conventions.md#cutting-a-release).

`release.yml` moves `v1` and `v1.4` onto the commit and opens a GitHub Release.
Prereleases (`v1.5.0-rc.1`) publish a release but deliberately do not move the
floating tags.

Cutting a new major line needs one extra step first:

```bash
scripts/pin-internal-refs.sh v2
git commit -am "chore: pin internal action references to v2"
```

## Commit messages

Conventional Commits — `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `ci:` —
matching the existing history. `release.yml` generates release notes from them.
