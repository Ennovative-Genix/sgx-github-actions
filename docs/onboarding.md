# Onboarding a repository

Target: first green deployment in under an hour.

## 1. AWS side, once per account

**OIDC provider.** One per AWS account:

- Provider URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

**Deployment role.** One per environment, with a trust policy scoped to the
specific repository — never `repo:Ennovative-Genix/*`:

```json
{
  "Effect": "Allow",
  "Principal": { "Federated": "arn:aws:iam::<account>:oidc-provider/token.actions.githubusercontent.com" },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
    "StringLike": { "token.actions.githubusercontent.com:sub": "repo:Ennovative-Genix/<your-repo>:environment:prod" }
  }
}
```

Scoping `sub` to `:environment:prod` means the role can only be assumed by a job
that declared `environment: prod` — and therefore only after that environment's
protection rules have been satisfied. This is the single highest-value control in
the setup.

Permissions the role needs, by target:

| Target | Permissions |
| --- | --- |
| All | `sts:GetCallerIdentity` |
| EC2 via S3 | `s3:PutObject`, `s3:GetObject`, `s3:ListBucket` on the build bucket; `ssm:SendCommand`, `ssm:GetCommandInvocation`; `secretsmanager:GetSecretValue` if used |
| ECR | `ecr:GetAuthorizationToken`, `ecr:BatchCheckLayerAvailability`, `ecr:PutImage`, `ecr:InitiateLayerUpload`, `ecr:UploadLayerPart`, `ecr:CompleteLayerUpload` |
| EKS | `eks:DescribeCluster`, plus an access entry or `aws-auth` mapping granting the role rights in-cluster |
| Lambda | `lambda:UpdateFunctionCode`, `lambda:PublishVersion`, `lambda:GetAlias`, `lambda:UpdateAlias`, `lambda:CreateAlias`, `lambda:GetFunction`, `lambda:ListVersionsByFunction` |
| S3 + CloudFront | `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`; `cloudfront:CreateInvalidation`, `cloudfront:GetInvalidation` |

**EC2 instances** additionally need the SSM agent running, Docker installed, and
an instance profile with read access to the build bucket. The instance pulls the
image itself; the runner never transfers it.

## 2. GitHub side, per repository

Create the environments you need under **Settings → Environments**. For each:

| Variable | Needed for | Example |
| --- | --- | --- |
| `AWS_REGION` | everything | `us-east-1` |
| `S3_BUILD_BUCKET` | EC2 path | `sgx-builds-prod` |
| `PORT_MAPPING` | EC2 path | `8080:8080` |
| `CLOUDWATCH_LOG_GROUP` | EC2 path, optional | `/sgx/billing-api` |
| `CLOUDWATCH_LOG_STREAM` | EC2 path, optional | `prod` |
| `STATIC_SITE_BUCKET` | static path | `sgx-web-prod` |
| `CLOUDFRONT_DISTRIBUTION_ID` | static path | `E1XXXXXXXXXXXX` |

`AWS_REGION` is not optional. Nothing is inferred from the branch name, so a run
without it fails at the credentials step rather than deploying somewhere
unintended.

Secrets, per environment:

| Secret | Needed for |
| --- | --- |
| `IAM_ROLE_ARN` | everything |
| `EC2_INSTANCE_ID` | EC2 path |
| `AWS_SECRETS_ARN` | EC2 path, if the container needs a `.env` |

On `prod`, add required reviewers and restrict deployment branches to `main`.

## 3. Add the workflow

Copy the closest file from [`examples/`](../examples/) into
`.github/workflows/`. Pin to `@v1`:

```yaml
uses: Ennovative-Genix/sgx-github-actions/.github/workflows/pipeline-ec2.yml@v1
```

| Your stack | Start from |
| --- | --- |
| Node.js service on EC2 | `examples/nodejs/` |
| NestJS API on EC2 | `examples/nestjs/` |
| Angular front end | `examples/angular/` |
| React front end | `examples/react/` |
| Nx monorepo | `examples/nx/` |
| Java service | `examples/java/` |
| Python service or Lambda | `examples/python/` |

## 4. Files your repository must provide

For the EC2 path, in `app_path`:

- `Dockerfile` — accepting `ARG ENV` and `ARG APP_VERSION`, both passed by the build
- `docker-compose.yml` — reading `IMAGE_NAME`, `PORT_MAPPING`, and optionally the CloudWatch variables

A compose file that works with this pipeline:

```yaml
services:
  app:
    image: ${IMAGE_NAME}:latest
    container_name: ${IMAGE_NAME}
    restart: unless-stopped
    ports:
      - "${PORT_MAPPING}"
    env_file:
      - .env
    logging:
      driver: awslogs
      options:
        awslogs-region: ${AWS_REGION}
        awslogs-group: ${CLOUDWATCH_LOG_GROUP}
        awslogs-stream: ${CLOUDWATCH_LOG_STREAM}
```

`container_name` must match `docker_image_name`: the start stage removes a
container by that name before bringing the new one up.

## 5. Verify

Deploy to `dev` first. A healthy run shows:

- **Build** — the version in the job summary, and an S3 upload of both `latest.tar.gz` and `<version>.tar.gz`
- **Load** — SSM command ids, each reaching `Success`
- **Start** — `docker compose ps` showing the container up

Then confirm rollback works *before* you need it:

```yaml
jobs:
  rollback:
    uses: Ennovative-Genix/sgx-github-actions/.github/workflows/rollback-ec2.yml@v1
    with:
      environment: dev
      docker_image_name: billing-api
      s3_path: billing-api/builds
      version: ${{ inputs.version }}
    secrets:
      IAM_ROLE_ARN: ${{ secrets.IAM_ROLE_ARN }}
      EC2_INSTANCE_ID: ${{ secrets.EC2_INSTANCE_ID }}
```

An untested rollback path is not a rollback path.

## Troubleshooting

| Symptom | Cause |
| --- | --- |
| `Credentials could not be loaded` | The job is missing `permissions: id-token: write` |
| `Not authorized to perform sts:AssumeRoleWithWebIdentity` | The trust policy `sub` does not match `repo:<org>/<repo>:environment:<env>` |
| `No such file or directory: docker-compose.yml` | `app_path` does not point at the directory holding it |
| SSM commands stay `Pending` and time out | SSM agent not running, or the instance profile lacks SSM permissions |
| `Missing bucket` | `S3_BUILD_BUCKET` is set on the repository rather than on the environment |
| `No AWS region` | `AWS_REGION` is not set on that environment; see step 2 |
| Build fails with `no space left on device` | Set `cleanup_runner: true` (default on `build-docker-s3.yml`) |
| Angular tests hang forever | Karma is in watch mode; `ci-node.yml` with `framework: angular` passes `--watch=false` |
