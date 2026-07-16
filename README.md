# sgx-github-actions

Centralized repository for reusable GitHub Actions workflows used across various projects.

> **Versioning:** consumers reference these workflows with `@main`, so any change merged here takes effect immediately for every consumer. Until tagged releases (`@v1`, …) are introduced, treat changes to this repo as breaking changes for all consumers.

## Available Workflows

### Deploy Workflow (`init.yml`)

Complete deployment pipeline that builds a Docker image, pushes it to **Amazon ECR**, and deploys it to **Kubernetes (EKS)** with `kubectl` against the consumer's own manifests.

**Usage:**

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/init.yml@main
    with:
      environment: dev # dev, uat, or prod
      env_region: ap-south-1 # AWS region for this environment
      docker_image_name: my-app
      app_path: packages/backend # Optional - path to Dockerfile if not in repo root
      # docker_context: .               # Optional - Docker build context; defaults to app_path. Use '.' for Nx/monorepos
      # ecr_repository: my-app          # Optional - defaults to docker_image_name
      # push_environment_tag: false     # Optional - also tag :<environment>; only if ECR tags are mutable
      # deployment_name: my-app         # Optional - defaults to docker_image_name
      # container_name: my-app          # Optional - defaults to docker_image_name
      # manifest_path: k8s/overlays/dev # Optional - auto-detected if omitted
      # namespace: dev                  # Optional - defaults to environment
    secrets:
      IAM_ROLE_ARN: ${{ secrets.IAM_ROLE_ARN }}
```

**Inputs:**

| Name                    | Required | Default             | Description                                                                 |
| ----------------------- | -------- | ------------------- | --------------------------------------------------------------------------- |
| `environment`           | Yes      | -                   | Target environment (`dev`, `qa`, `uat`, `stg`, `preprod`, `prod`)           |
| `env_region`            | Yes      | -                   | AWS region for this environment (ECR + EKS)                                 |
| `docker_image_name`     | Yes      | -                   | Image name; default ECR repo / Deployment / container name                  |
| `app_path`              | No       | `.`                 | Path to the directory containing the `Dockerfile`                           |
| `docker_context`        | No       | `app_path`          | Docker build context. Set to `.` for Nx/monorepo root `COPY`s               |
| `ecr_repository`        | No       | `docker_image_name` | ECR repository name                                                         |
| `push_environment_tag`  | No       | `false`             | Also push `:<environment>`. Use `true` only if ECR tag immutability is off  |
| `deployment_name`       | No       | `docker_image_name` | Kubernetes Deployment to update                                             |
| `container_name`        | No       | `docker_image_name` | Container within the Deployment to set the new image on                     |
| `manifest_path`         | No       | _auto_              | kustomize dir or plain manifests in your repo (see below)                   |
| `namespace`             | No       | `environment`       | Kubernetes namespace to deploy into                                         |

**Secrets:**

| Name           | Required | Description                                       |
| -------------- | -------- | ------------------------------------------------- |
| `IAM_ROLE_ARN` | Yes      | AWS IAM Role ARN for OIDC (ECR push + EKS access) |

**Pipeline Steps:**

1. **Validate inputs** - Fails closed before any AWS credentials are assumed if `environment` isn't `dev`/`uat`/`prod` or `docker_image_name`/`app_path` contain unexpected characters.
2. **Build and Push to ECR** (`build-ecr.yml`) - OIDC → ECR login → Buildx build (with `ENV=<environment>` build arg and a `type=gha` layer cache) → `docker push`. Always tags `:<git-sha>`; optionally also `:<environment>` when `push_environment_tag: true`. Deploy uses the digest-pinned image reference.
3. **Deploy to Kubernetes** (`deploy-k8s.yml`) - OIDC → `aws eks update-kubeconfig` → `kubectl apply` your manifests → `kubectl set image` (digest-pinned) → `kubectl rollout status` with **automatic rollback** to the previous revision on failure.

> Runs are serialized per `environment` + `docker_image_name` via a `concurrency` group, so two deploys to the same target won't race.

---

### Individual Workflows

These workflows are used internally by `init.yml` but can also be called directly:

#### `build-ecr.yml`

Builds a Docker image (Buildx + GitHub Actions layer cache) and pushes it to Amazon ECR.

- Builds with `ENV=<environment>` passed as a build arg; any environment-specific build logic lives inside your `Dockerfile`
- Layer cache is keyed by `docker_image_name` (`type=gha` scope), so unchanged layers are reused across runs
- Always pushes `:<git-sha>` (works with ECR immutable tags)
- Optionally also pushes `:<environment>` when `push_environment_tag: true` (requires mutable ECR tags)
- Outputs a **digest-pinned** image reference (`repo@sha256:…`) consumed by the deploy step

#### `deploy-k8s.yml`

Deploys the image to EKS over `kubectl`:

- OIDC → `aws eks update-kubeconfig` (no static kubeconfig secret; region from `env_region`, cluster from `EKS_CLUSTER_NAME`)
- Applies your manifests (kustomize overlay or plain), then pins the named container to the built digest
- Waits on `kubectl rollout status`; on failure dumps diagnostics and **rolls back** to the previous revision (first deploy has no rollback target)

**Manifest resolution** (`manifest_path`): if omitted, the deploy looks for `k8s/overlays/<environment>/` (kustomize), else falls back to `k8s/`. A `kustomization.yaml` triggers `kubectl apply -k`; otherwise `kubectl apply -f` over the directory.

---

## Required Repository Setup

### Environment Variables (Repository Variables)

Set these in your repository's Settings > Environments > [environment] > Environment variables:

| Variable                  | Required | Description                                                                  |
| ------------------------- | -------- | ---------------------------------------------------------------------------- |
| `EKS_CLUSTER_NAME`        | Yes      | Target EKS cluster name for this environment                                 |
| `EKS_BASTION_INSTANCE_ID` | Yes*     | Bastion EC2 instance ID for SSM port-forward to a **private** EKS API (`i-…`) |

\*Required when the EKS API endpoint is private (not reachable from GitHub-hosted runners).

### Secrets

Set these in your repository's Settings > Secrets and variables > Actions:

| Secret         | Required | Description                                                  |
| -------------- | -------- | ------------------------------------------------------------ |
| `IAM_ROLE_ARN` | Yes      | AWS IAM Role ARN for OIDC (ECR push + `eks:DescribeCluster`) |

### Required Files in Your Repository

- `Dockerfile` in `app_path` - environment-specific logic should key off the `ENV` build arg. For Nx/monorepos whose Dockerfile `COPY`s from the repo root, set `docker_context: '.'` (context defaults to `app_path`).
- **Kubernetes manifests** - a `kustomize` overlay (`k8s/overlays/<environment>/kustomization.yaml`) or plain manifests (`k8s/`). Your `Deployment` should be named `docker_image_name` (or set `deployment_name`) with a container named `docker_image_name` (or set `container_name`). Define readiness/liveness probes so `rollout status` reflects real serving health.

### Application secrets

The pipeline does not handle application secrets. Your app fetches them at runtime from AWS (e.g. Secrets Manager) via the AWS SDK, using **IRSA / Pod Identity** — annotate the pod's ServiceAccount with an IAM role that has `secretsmanager:GetSecretValue`. No secret material passes through the CI runner.

---

## AWS Region

The region is passed explicitly per call via the **`env_region`** input, used by both build (ECR) and deploy (EKS). Ensure the environment's ECR repository and EKS cluster both live in that region.

---

## AWS Prerequisites

1. **OIDC Provider** configured for GitHub Actions
2. **IAM Role** (assumed via OIDC by CI) with permissions for:
   - ECR (push/pull to the app repository)
   - EKS (`eks:DescribeCluster`) plus an **EKS access entry** granting edit on the target namespace
   - For **private EKS**: SSM Session Manager to the bastion (`ssm:StartSession` on the bastion instance + document `AWS-StartPortForwardingSessionToRemoteHost`; typically also `ssm:TerminateSession`). Bastion must be SSM-managed (`AmazonSSMManagedInstanceCore`) and able to reach the EKS API on `:443` inside the VPC.
3. **Amazon ECR repository** for the image (per region)
4. **EKS cluster** for the environment, with the target namespace (auto-created if missing); set `EKS_CLUSTER_NAME` (and `EKS_BASTION_INSTANCE_ID` if private) per environment
5. **IRSA / Pod Identity** for the app's ServiceAccount if the app reads secrets at runtime (e.g. `secretsmanager:GetSecretValue`)
6. **GitHub Environments** `dev`/`uat`/`prod` created in each consumer repo (so environment protection rules and the OIDC `environment` claim apply)

---

## Developer

Navdeep Singh
Email: navdeep.singh@solugenix.com
