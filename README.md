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
      # deployment_name: my-app         # Optional - defaults to docker_image_name
      # container_name: my-app          # Optional - defaults to docker_image_name
      # manifest_path: k8s/overlays/dev # Optional - auto-detected if omitted
      # namespace: dev                  # Optional - defaults to environment
      # aws_secret_arn: ...            # Optional override (prefer passing secret below)
      # k8s_secret_name: my-app-secrets   # Required if aws_secret_arn/AWS_SECRET_ARN is set; must match Deployment envFrom
    secrets:
      IAM_ROLE_ARN: ${{ secrets.IAM_ROLE_ARN }}
      AWS_SECRET_ARN: ${{ secrets.AWS_SECRET_ARN }}  # Environment secret — pass explicitly
```

**Inputs:**

| Name                | Required | Default               | Description                                                        |
| ------------------- | -------- | --------------------- | ------------------------------------------------------------------ |
| `environment`       | Yes      | -                     | Target environment (`dev`, `qa`, `uat`, `stg`, `preprod`, `prod`)  |
| `env_region`        | Yes      | -                     | AWS region for this environment (ECR + EKS)                        |
| `docker_image_name` | Yes      | -                     | Image name; default ECR repo / Deployment / container name         |
| `app_path`          | No       | `.`                   | Path to the directory containing the `Dockerfile`                  |
| `docker_context`    | No       | `app_path`            | Docker build context. Set to `.` for Nx/monorepo root `COPY`s      |
| `ecr_repository`    | No       | `docker_image_name`   | ECR repository name                                                |
| `deployment_name`   | No       | `docker_image_name`   | Kubernetes Deployment to update                                    |
| `container_name`    | No       | `docker_image_name`   | Container within the Deployment to set the new image on            |
| `manifest_path`     | No       | _auto_                | kustomize dir or plain manifests in your repo (see below)          |
| `namespace`         | No       | `environment`         | Kubernetes namespace to deploy into                                |
| `aws_secret_arn`    | No       | _(empty)_             | Optional ARN override; prefer `secrets.AWS_SECRET_ARN`             |
| `k8s_secret_name`   | No*      | _(empty)_             | Kubernetes Secret name (must match Deployment `envFrom`)           |

\*Required whenever `aws_secret_arn` / `AWS_SECRET_ARN` is set — the sync step fails closed with `K8S_SECRET_NAME resolved empty` if it's missing, rather than silently syncing under a name that may not match your Deployment.

**Secrets:**

| Name             | Required | Description                                                                 |
| ---------------- | -------- | --------------------------------------------------------------------------- |
| `IAM_ROLE_ARN`   | Yes      | AWS IAM Role ARN for OIDC (ECR push + EKS access)                           |
| `AWS_SECRET_ARN` | No*      | Secrets Manager ARN; pass from caller Environment secret into this workflow |

\*Required when the Deployment uses `envFrom` with the synced Kubernetes Secret. Nested reusable workflows do **not** auto-expose Environment secrets — pass `AWS_SECRET_ARN` explicitly (same pattern as `IAM_ROLE_ARN`). Do not put `environment:` on the caller job that uses this workflow (`uses:` + `environment:` is invalid).

Resolution order in deploy: `inputs.aws_secret_arn` → `secrets.AWS_SECRET_ARN` → `vars.AWS_SECRET_ARN`.

**Pipeline Steps:**

1. **Validate inputs** - Fails closed before any AWS credentials are assumed if `environment` isn't `dev`/`uat`/`prod` or `docker_image_name`/`app_path` contain unexpected characters.
2. **Build and Push to ECR** (`build-ecr.yml`) - OIDC → ECR login → Buildx build (with `ENV=<environment>` build arg and a `type=gha` layer cache) → `docker push`. Tags the immutable `:<git-sha>` (the deploy handle) and a moving `:<environment>` tag. Only changed layers are transferred. Outputs a digest-pinned image reference.
3. **Deploy to Kubernetes** (`deploy-k8s.yml` / `deploy-k8s-kubeadm.yml`) - OIDC → SSM tunnel → optional **Secrets Manager ARN → Kubernetes Secret sync** → `kubectl apply` → `kubectl set image` → `kubectl rollout status` with **automatic rollback** on failure (EKS).
4. **Refresh secrets** (last job; always runs when `k8s_secret_name` is set) - `refresh-secrets-eks` / `refresh-secrets-kubeadm`. Does **not** need the ECR build. Syncs Secrets Manager → Kubernetes Secret, then `kubectl rollout restart` without changing the running image. After updating AWS Secrets Manager, open the last successful run → **Refresh secrets** → **Re-run job** (do not start a new workflow). GitHub only re-runs this job plus validate, not build/deploy.

> Runs are serialized per `environment` + `docker_image_name` via a `concurrency` group, so two deploys to the same target won't race.

---

### Individual Workflows

These workflows are used internally by `init.yml` but can also be called directly:

#### `build-ecr.yml`

Builds a Docker image (Buildx + GitHub Actions layer cache) and pushes it to Amazon ECR.

- Builds with `ENV=<environment>` passed as a build arg; any environment-specific build logic lives inside your `Dockerfile`
- Layer cache is keyed by `docker_image_name` (`type=gha` scope), so unchanged layers are reused across runs
- Pushes `:<git-sha>` (immutable deploy handle) and `:<environment>` (moving convenience tag)
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
| `AWS_SECRET_ARN`          | No       | Optional fallback ARN if not passed as a secret (same value as the secret)   |

\*Required when the EKS API endpoint is private (not reachable from GitHub-hosted runners).

### Secrets

Set these in your repository's Settings > Environments > [environment] > Environment secrets (and pass them into `init.yml`):

| Secret           | Required | Description                                                  |
| ---------------- | -------- | ------------------------------------------------------------ |
| `IAM_ROLE_ARN`   | Yes      | AWS IAM Role ARN for OIDC (ECR push + `eks:DescribeCluster`) |
| `AWS_SECRET_ARN` | No*      | Full Secrets Manager ARN to sync into the cluster            |

\*Pass explicitly: `secrets: { AWS_SECRET_ARN: ${{ secrets.AWS_SECRET_ARN }} }`. If the caller job cannot resolve Environment secrets (no `environment:` with `uses:`), also add the same ARN as a **Repository** secret or Environment **variable**.

When `aws_secret_arn` / `secrets.AWS_SECRET_ARN` / `vars.AWS_SECRET_ARN` is set, deploy syncs that **AWS Secrets Manager** secret into a **Kubernetes Secret** named by `k8s_secret_name` before applying manifests — you must set `k8s_secret_name` to match your Deployment's `envFrom.secretRef.name` (there is no default; the sync step fails closed if it's left empty).

**Supported SecretString formats:**
- JSON object: `{"MONGO_URI":"...","JWT_SECRET":"..."}`
- Dotenv / properties plaintext: `MONGO_URI=...` or legacy `CLOUDWATCH_LOG_GROUP:/aws/...` (`KEY:value` is normalized to `KEY=value` for Kubernetes)

A single raw value with no key is not supported.

### Required Files in Your Repository

- `Dockerfile` in `app_path` - environment-specific logic should key off the `ENV` build arg. For Nx/monorepos whose Dockerfile `COPY`s from the repo root, set `docker_context: '.'` (context defaults to `app_path`).
- **Kubernetes manifests** - a `kustomize` overlay (`k8s/overlays/<environment>/kustomization.yaml`) or plain manifests (`k8s/`). Your `Deployment` should be named `docker_image_name` (or set `deployment_name`) with a container named `docker_image_name` (or set `container_name`). Define readiness/liveness probes so `rollout status` reflects real serving health.

### Application secrets

- Pass `AWS_SECRET_ARN` into `init.yml` (see Secrets table above); region is parsed from the ARN (EKS and the secret may differ, e.g. `us-east-1` / `ap-south-1`).
- The CI IAM role needs `secretsmanager:GetSecretValue` on that ARN.
- Secret payload values are never logged.

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
