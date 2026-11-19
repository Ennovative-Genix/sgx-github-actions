# Shared Nova branching automation

Reusable composite actions + workflow wrappers for the org branching strategy:

| Piece | Purpose |
| --- | --- |
| `backmerge-main` | On push to `main`, open/refresh PRs `main → development` and `main → release/*` |
| `backmerge-notify` | Weekday / PR sync: comment (+ optional Teams) when back-merge PRs conflict or go stale |
| `branch-guards` | Enforce allowed head names; `main` only accepts `release/*` or `hotfix/*` |

## Use in an app repo (recommended)

Thin local workflows that call the reusable wrappers (same pattern as deploy `init.yml`):

```yaml
# .github/workflows/backmerge-main.yml
name: Back-merge from main
on:
  push:
    branches: [main]
  workflow_dispatch:
permissions:
  contents: read
  pull-requests: write
jobs:
  backmerge:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/branching-backmerge-main.yml@chore/branching-strategy
```

```yaml
# .github/workflows/backmerge-notify.yml
name: Back-merge notify
on:
  schedule:
    - cron: '30 4 * * 1-5'
  pull_request:
    types: [synchronize, reopened]
  workflow_dispatch:
permissions:
  contents: read
  pull-requests: write
jobs:
  notify:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/branching-backmerge-notify.yml@chore/branching-strategy
    secrets: inherit   # optional TEAMS_WEBHOOK_BRANCHING
```

```yaml
# .github/workflows/branch-guards.yml
name: Branch guards
on:
  pull_request:
    types: [opened, synchronize, reopened, edited]
    branches: [main, development, 'release/**', 'hotfix/**']
permissions:
  contents: read
  pull-requests: write
jobs:
  guards:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/branching-guards.yml@chore/branching-strategy
```

Pin `@chore/branching-strategy` until you cut a stable tag (e.g. `@branching-v1`).

## Optional secret

| Secret | Repo | Purpose |
| --- | --- | --- |
| `TEAMS_WEBHOOK_BRANCHING` | each app repo | Incoming Webhook / Power Automate URL for Teams notify |
