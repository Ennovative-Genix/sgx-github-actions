# sgx-github-actions

Centralized repository for reusable GitHub Actions workflows used across various projects.

## Available Workflows

### Deploy Workflow (`deploy-init.yml`)

Complete deployment pipeline that builds, uploads to S3, and deploys to EC2.

**Usage:**

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/deploy-init.yml@main
    with:
      environment: dev # dev, uat, or prod
      docker_image_name: my-app
      s3_path: my-app/builds
    secrets:
      IAM_ROLE_ARN: ${{ secrets.IAM_ROLE_ARN }}
      EC2_INSTANCE_ID: ${{ secrets.EC2_INSTANCE_ID }}
      AWS_SECRETS_ARN: ${{ secrets.AWS_SECRETS_ARN }} # Optional
```

**Inputs:**

| Name                | Required | Description                               |
| ------------------- | -------- | ----------------------------------------- |
| `environment`       | Yes      | Target environment (`dev`, `uat`, `prod`) |
| `docker_image_name` | Yes      | Docker image name                         |
| `s3_path`           | Yes      | S3 path prefix for uploads/downloads      |

**Secrets:**

| Name              | Required | Description                              |
| ----------------- | -------- | ---------------------------------------- |
| `IAM_ROLE_ARN`    | Yes      | AWS IAM Role ARN for OIDC authentication |
| `EC2_INSTANCE_ID` | Yes      | Target EC2 Instance ID                   |
| `AWS_SECRETS_ARN` | No       | AWS Secrets Manager ARN for .env file    |

**Pipeline Steps:**

1. **Pre-Build Cleanup** - Frees up disk space on runner
2. **Build and Upload** - Builds project, creates Docker image, uploads to S3
3. **Load Docker to EC2** - Copies Docker image from S3 to EC2 and loads it
4. **Start Container** - Optionally fetches .env from Secrets Manager, copies docker-compose.yml, and starts container

---

### Test Workflow (`test-init.yml`)

Run tests for your project with framework-specific configurations.

**Usage:**

```yaml
name: Test

on:
  pull_request:
    branches: [main]

jobs:
  test:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/test-init.yml@main
    with:
      framework: angular
      node_version: "20.x"
      run_tests: true
```

**Inputs:**

| Name           | Required | Default   | Description               |
| -------------- | -------- | --------- | ------------------------- |
| `framework`    | No       | `angular` | Framework under test      |
| `node_version` | No       | `20.x`    | Node.js version to use    |
| `run_tests`    | No       | `true`    | Whether to run test cases |

---

### Individual Workflows

These workflows are used internally by the main workflows but can also be called directly:

#### `build-docker-s3.yml`

Builds the project, creates a Docker image, and uploads to S3.

- Supports environment-specific builds (`npm run build:dev`, `build:uat`, `build:prod`)
- Falls back to `npm run build` if environment-specific script doesn't exist
- Uploads to S3 with both `latest.tar.gz` and `{sha}.tar.gz` versions

#### `deploy-ec2-load-docker.yml`

Copies Docker image from S3 to EC2 and loads it into Docker.

#### `deploy-ec2-start-container.yml`

Starts the Docker container on EC2:

- Optionally fetches `.env` from AWS Secrets Manager
- Copies `docker-compose.yml` to EC2
- Stops existing container and starts new one
- Cleans up temporary files

#### `prebuild-cleanup.yml`

Frees up disk space on GitHub runners by removing unnecessary packages.

#### `test-angular.yml`

Runs Angular-specific tests.

---

## Required Repository Setup

### Environment Variables (Repository Variables)

Set these in your repository's Settings > Environments > [environment] > Environment variables:

| Variable                | Description                           |
| ----------------------- | ------------------------------------- |
| `S3_BUILD_BUCKET`       | S3 bucket name for storing builds     |
| `PORT_MAPPING`          | Docker port mapping (e.g., `8080:80`) |
| `CLOUDWATCH_LOG_GROUP`  | CloudWatch log group name             |
| `CLOUDWATCH_LOG_STREAM` | CloudWatch log stream name            |

### Secrets

Set these in your repository's Settings > Secrets and variables > Actions:

| Secret            | Description                                                |
| ----------------- | ---------------------------------------------------------- |
| `IAM_ROLE_ARN`    | AWS IAM Role ARN for OIDC authentication                   |
| `EC2_INSTANCE_ID` | Target EC2 Instance ID                                     |
| `AWS_SECRETS_ARN` | (Optional) AWS Secrets Manager ARN containing .env content |

### Required Files in Your Repository

- `Dockerfile` - For building the Docker image
- `docker-compose.yml` - For running the container on EC2
- `package.json` - With build scripts (`build`, `build:dev`, `build:uat`, `build:prod`)

---

## AWS Prerequisites

1. **OIDC Provider** configured for GitHub Actions
2. **IAM Role** with permissions for:
   - S3 (read/write to build bucket)
   - SSM (SendCommand, GetCommandInvocation)
   - Secrets Manager (GetSecretValue) - if using AWS_SECRETS_ARN
3. **EC2 Instance** with:
   - SSM Agent installed and running
   - Docker installed
   - IAM Instance Profile with S3 read access

---

## Developer

Navdeep Singh
Email: navdeep.singh@solugenix.com
