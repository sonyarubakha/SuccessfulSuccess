# SuccessfulSuccess — Meetings

[![Style](https://github.com/dobosevych/SuccessfulSuccess/actions/workflows/style.yml/badge.svg)](https://github.com/dobosevych/SuccessfulSuccess/actions/workflows/style.yml)

A small web app for today's meetings: see what is on today (name, description,
participants) and add a new one from the UI. Built to `SPEC.md`.

- **Frontend** — Next.js (App Router) + shadcn/ui, styled after Canva's visual language
- **Backend** — FastAPI + SQLAlchemy 2 (async) + Alembic
- **Database** — PostgreSQL 17

## Quick start

```bash
cp .env.example .env
docker compose up --build
```

Then open:

| What | URL |
|------|-----|
| App | http://localhost:3000 |
| API docs (Swagger) | http://localhost:8000/docs |
| Health check | http://localhost:8000/health |

The backend applies migrations on start.

### Sign-in (Cognito)

Every page except the login page, and every `/api/v1` endpoint, needs a
signed-in user, and each user sees only their own meetings. Sign-in is an AWS
Cognito user pool (`infra/auth.tf`, managed by HCP Terraform): email + password, and Google when it is
configured. Even for local development the pool lives in AWS (it is free at
this scale):

```bash
make aws-auth-env      # prints COGNITO_* lines: paste them into .env
docker compose up -d   # restart so the API and the frontend pick them up
```

**Google sign-in** uses the existing Google OAuth client. Keep its secret in the
sensitive HCP workspace variable `google_client_secret`; its public client ID is
`google_client_id`. Review changes through the HCP VCS workflow below. Read the
public redirect URI with `terraform -chdir=infra output -raw google_redirect_uri`
and ensure it is registered with Google. Cognito callback/logout URLs are managed
by `app_urls`, including the local development URL. Changing `.env` does not
update the Terraform-managed pool.

The first time someone signs in, the frontend sends their ID token to
`POST /api/v1/me/sync`, which stores their profile (email, name, picture,
provider, last login) in the `users` table. Meetings reference `users.id`, the
Cognito `sub`.

Demo data is per user: `make seed owner=<sub>` adds a few meetings for today to
that user (their `sub` is on the user's page in the Cognito console, or `id` in
`GET /api/v1/me`).

> **Ports already in use?** Every host port is configurable in `.env`
> (`FRONTEND_PORT`, `BACKEND_PORT`, `POSTGRES_PORT`). If you change the frontend
> or backend port, update `CORS_ORIGINS` and `NEXT_PUBLIC_API_BASE_URL` to match —
> the browser talks to the published host port, not the compose service name.

## Common tasks

```bash
make up          # start the stack
make down        # stop it
make down-v      # stop it and drop the database volume
make test        # backend test suite (creates meetings_test automatically)
make lint        # ruff + eslint
make migrate     # alembic upgrade head
make seed owner=<sub>  # demo meetings for today for one user
make psql        # psql shell against the app database
make help        # everything else
```

## Windows

The same `make` targets work on Windows, with Docker Desktop (WSL 2 backend)
and [Git for Windows](https://git-scm.com/download/win) installed. There is no
need to install GNU make first: `make.cmd` in the repository root runs the
Makefile, and when `make.exe` is missing it offers to install it with winget
(`ezwinports.make`) and carries on.

```powershell
Copy-Item .env.example .env
.\make help        # PowerShell only runs scripts from the current folder with .\
.\make up-build
```

In `cmd.exe`, plain `make help` finds `make.cmd`; once make is installed,
`make help` works everywhere.

Every recipe runs in Git's bash (`C:/Program Files/Git` by default; pass
`GIT_HOME=...` if it is installed elsewhere), so `make test`, `make seed`, the
`aws-*` targets and the rest behave as on macOS and Linux. Inside WSL, plain
`make` works as on Linux.

Things that are already taken care of, and why:

- `.gitattributes` checks every file out with LF line endings. Git on Windows
  converts to CRLF by default, and a CRLF `entrypoint.sh` stops the backend
  container with `exec /app/entrypoint.sh: no such file or directory`. A clone
  made before `.gitattributes` existed keeps its CRLF files until you run
  `git rm --cached -r . && git reset --hard` (this discards local changes).
- File-change events from a Windows folder do not reach the containers, so hot
  reload polls: `WATCHPACK_POLLING` for Next.js, `WATCHFILES_FORCE_POLLING` for
  uvicorn. For faster reloads keep the clone inside WSL rather than on `C:\`.
- Git's bash rewrites arguments that look like paths (`/aws` becomes
  `C:/Program Files/Git/aws`); the Makefile turns that off with
  `MSYS_NO_PATHCONV`.
- Keep `.env` with LF line endings (copying `.env.example` does): `make` reads
  it directly, and a CRLF `.env` leaves a stray `\r` on every value.

## Deploy to AWS

Infrastructure has two owners after Lab 7:

| Owner | Infrastructure | Configuration |
|---|---|---|
| HCP Terraform | Cognito Auth, weekly Reports, AI parser: 40 managed resources | `infra/auth.tf`, `reports.tf`, `ai.tf` |
| CloudFormation | Shared ECR, serverless API/database/network, compatibility API distribution, frontend | `infra/ecr.yml`, `backend-serverless.yml`, `backend.yml`, `frontend.yml` |

The original Auth, Reports and AI stacks were removed after their resources were
retained and imported. Their YAML templates are historical migration references;
do not deploy them again. Older CloudFormation infrastructure stays under its
existing ownership. See [ADR 0007](docs/adr/0007-terraform.md) for the migration.

### HCP Terraform: VCS-driven infrastructure workflow

| Setting | Value |
|---|---|
| Organization | `successfulsuccess-lab7-org` |
| Workspace | `successfulsuccess-lab7` |
| GitHub repository / branch | `dobosevych/SuccessfulSuccess` / `lab7` |
| Terraform working directory | `infra` |
| Execution and state | Remote execution; state stored in HCP Terraform |
| Approval | Manual Apply enabled; Auto-apply disabled |

Open the [HCP workspace](https://app.terraform.io/app/successfulsuccess-lab7-org/workspaces/successfulsuccess-lab7).

1. Edit Terraform configuration or reviewed non-sensitive inputs in
   `infra/lab7.auto.tfvars`. Preserve the committed `.terraform.lock.hcl` unless
   deliberately reviewing a provider upgrade.
2. Run `terraform -chdir=infra fmt -check`,
   `terraform -chdir=infra validate` and `git diff --check` locally. A fresh
   checkout needs provider initialization first.
3. Review the diff, then commit and push to `lab7` when authorized. GitHub VCS
   integration queues the remote run from `infra`; local `terraform.tfvars` is
   ignored and is not available to that run.
4. Review the HCP plan for the exact commit. Check additions, updates,
   replacements, deletions and output changes. Investigate unexpected changes;
   discard an unsafe run rather than approving it.
5. An authorized reviewer manually confirms Apply in HCP. No-change runs need no
   apply. Inspect the completed run and the next no-change plan.

Do not run local Terraform apply, import or destroy for this VCS-managed
infrastructure. Make does not execute Terraform mutations. `make infra-workflow`
prints the workflow and workspace URL.

**Output-only demonstration:** `report_queue_name` in `infra/outputs.tf` reads the
existing queue name. Once this change is reviewed and pushed, the expected HCP
plan has **0 resource additions, 0 resource changes, 0 resource deletions** and
one added output. Review and manually apply that run in HCP to publish the output
to remote state. The output is unavailable to state readers until that apply;
none of the existing Make commands depends on it yet.

### Credentials, variables and state

HCP runs authenticate to AWS with OIDC dynamic credentials, using
`TFC_AWS_PROVIDER_AUTH=true` and the configured `TFC_AWS_RUN_ROLE_ARN`. AWS trust
must constrain the audience `aws.workload.identity` and the exact organization,
project (`Default Project`), workspace and approved plan/apply phases. The default
AWS provider and `aws.untagged` share the same credentials; the alias avoids
adding default tags to the existing untagged security-group rule. Do not add
long-lived AWS keys to Git or workspace Terraform variables. A read-only AWS role
supports refresh and output-only changes; future infrastructure changes require
separately reviewed permissions.

The 27 non-sensitive VCS inputs live in `infra/lab7.auto.tfvars`: resource names,
IDs, public endpoints, image digests and application settings. Configure
`db_password`, `google_client_secret`, `report_recipients` and `budget_email` as
sensitive **Terraform** workspace variables. Keep overlapping workspace inputs
consistent with the checked-in configuration. `.env`, private `*.tfvars`, state
and saved plans stay ignored; only the reviewed `lab7.auto.tfvars` is exempt.

Sensitive input annotations redact normal output but do not remove secrets from
state. Restrict HCP state/run access and cross-workspace sharing, protect tokens,
and avoid raw state exports, all-output JSON dumps or debug logs in shared logs.
Do not print the Google secret or password-bearing database URLs.

For local read-only access to the public outputs used by Make, install Terraform
and authenticate to HCP with an account allowed to read this workspace's outputs:

```bash
terraform login
terraform -chdir=infra init -lockfile=readonly
make infra-ready
make aws-auth-env
terraform -chdir=infra output -raw google_redirect_uri
```

Initialization connects the existing workspace and installs locked providers; it
is not an import, apply or state migration. Stop if initialization proposes moving
state or selecting another workspace. The Make targets read selected public
outputs using `terraform output -raw`; never use this option for secret outputs.
Local AWS credentials are separate from the OIDC credentials issued inside HCP.
See HashiCorp's [VCS workflow](https://developer.hashicorp.com/terraform/cloud-docs/workspaces/run/ui),
[AWS dynamic credentials](https://developer.hashicorp.com/terraform/cloud-docs/dynamic-provider-credentials/aws-configuration)
and [output command](https://developer.hashicorp.com/terraform/cli/commands/output).

### Legacy CloudFormation application workflows

Use an authenticated AWS CLI (`AWS=aws` by default), Docker and Make. Local
application/deployment settings still come from the gitignored `.env`. Never
commit AWS credentials or database passwords. These targets continue to operate
on older CloudFormation infrastructure and application code:

```bash
make aws-whoami
make aws-deploy-backend    # ECR build/push, serverless API/database and compatibility API, migrations
make aws-deploy-frontend   # frontend CloudFormation, static build/upload and invalidation
make aws-deploy            # backend then frontend, using existing HCP Auth/AI outputs
make aws-release-backend   # release code to the legacy API Lambda, then migrations
make aws-url
make aws-status
make aws-logs
make aws-migrate
```

Backend and frontend deployment first check access to existing HCP outputs.
Cognito IDs/issuer and the AI parser URL now come from Terraform state. The
backend still fetches the issuer's JWKS and passes it to its private-VPC Lambda;
shared database, VPC and backend outputs still come from CloudFormation.
`aws-release-backend` updates only the legacy API function, not the Terraform
Reports or parser functions.

`make aws-deploy-auth`, `make aws-deploy-reports` and `make aws-deploy-ai` now
fail with guidance to the HCP workflow. They do not build/push images or recreate
stacks. To release Reports/AI code, build/push with the existing ECR tooling when
authorized, set the reviewed immutable digest in `reports_image_uri` or
`ai_image_uri`, and use a GitHub-triggered plan and manual HCP approval. An image
push alone does not update those Terraform-managed functions.

`make report-now WEEK=YYYY-Www` reads `report_queue_url` from HCP and sends a real
SQS message; it can generate a report and email. Run it only when that operational
action is intended, never as a harmless infrastructure validation.

The API uses `backend/Dockerfile.lambda` and a Lambda Function URL with Aurora in
the default VPC. The compatibility API distribution and frontend retain their
CloudFormation deployment paths. Images default to `linux/amd64` with
`--provenance=false`, matching the legacy API's configured `x86_64` architecture.
The local Compose stack continues to use `backend/Dockerfile`.

Frontend builds use the API URL plus public Cognito/parser outputs. If the
frontend domain or local port changes, review Cognito callback/logout `app_urls`
and parser `cors_origins` through Terraform before relying on the new origin.
Frontend deployment no longer redeploys Cognito automatically. Legacy API CORS
still follows `AWS_CORS_ORIGINS`/the frontend outputs via `make aws-deploy-backend`.

For an optional frontend domain, set `AWS_FRONTEND_DOMAIN` in `.env`, run
`make aws-frontend-cert` and deploy the frontend. Certificate validation and
frontend Route 53 configuration remain CloudFormation/tooling responsibilities.
Review the Terraform origin/callback changes and redeploy legacy API CORS as
needed. CloudFront certificates must be in `us-east-1`.

### Operational boundaries

`make aws-destroy` is a **partial, destructive teardown** of the legacy frontend
and compatibility API distribution only. It asks for confirmation and empties the
frontend bucket. It preserves the shared serverless API/database, ECR repository
and all Terraform resources. Full teardown needs a separate dependency review:
Terraform Reports uses the legacy backend's database/network, and both ownership
sets use ECR images. Deleting the registry would break deployed Lambdas.

ECR automatic image expiration is disabled after a policy deleted deployed image
digests during migration. Keep deployed digests available; do not prune images
based only on age or tag count. Storage grows until a separately reviewed cleanup
strategy is introduced. The original Reports image was restored exactly, and both
Reports functions were reactivated before the retention migration completed.

Temporary migration ignores cover the Google `client_secret` and builder
`DATABASE_URL` individual map entries because import plans showed identical
values with differing sensitivity metadata. They also suppress genuine changes
to those fields while present. Review them individually after import, privately
compare values, remove one ignore and inspect a fresh remote plan before any
approval. Keep both input variables sensitive and never use blanket ignores.
Separate Google discovery-field ignores preserve AWS-populated OAuth metadata.
Cognito pool/client/branding and the reports bucket retain `prevent_destroy`
safeguards. See the ADR for remaining tradeoffs and the migration record.

## API

Base path `/api/v1`. Full schema at `/docs`. Everything under it needs
`Authorization: Bearer <Cognito access token>` (`401` otherwise) and only ever
touches the caller's own meetings: someone else's meeting is a `404`.

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/meetings?date=&q=&limit=&offset=` | Meetings overlapping a day (today by default) |
| `GET` | `/meetings/{id}` | One meeting |
| `POST` | `/meetings` | Create a meeting |
| `PUT` | `/meetings/{id}` | Replace a meeting's details and participants |
| `DELETE` | `/meetings/{id}` | Delete a meeting and its participants |
| `GET` | `/me` | The signed-in user's profile |
| `POST` | `/me/sync` | Store the profile from the user's ID token (after sign-in) |
| `GET` | `/health` | Liveness + database check |

Every error uses one envelope:

```json
{ "error": { "code": "validation_error", "message": "…", "details": [{ "field": "ends_at", "message": "…" }] } }
```

### Time handling

Timestamps are stored in UTC and **served with the application timezone's offset**
(`APP_TIMEZONE`, default `Europe/Kyiv`). "Today" is that timezone's calendar day,
and a meeting is listed if it *overlaps* the day — so a 23:00–00:30 meeting appears
on both days. The UI reads the wall-clock time straight from the offset the API
sent, so every client shows the same time as the day it was listed under.

## Layout

```
backend/    FastAPI app (api → services → repositories → models), Alembic, tests
frontend/   Next.js app, shadcn/ui primitives in components/ui
infra/      Terraform Auth/Reports/AI plus legacy CloudFormation templates
docker-compose.yml
```

## Continuous integration

`.github/workflows/style.yml` runs on pushes to all branches and gates style:

| Job | Runs | Against |
|-----|------|---------|
| Backend — ruff | `ruff check` (GitHub annotations) + `ruff format --diff` | `backend/` |
| Frontend — ESLint | `npm ci` + `npm run lint` | `frontend/` |

Ruff is pinned to the version the backend image ships (0.16.6) and Node matches
the container's Node 22, so CI and local containers agree on what passes.

Reproduce either job locally:

```bash
make lint                                   # both, through the running containers
cd backend  && uvx ruff@0.16.6 check . && uvx ruff@0.16.6 format --diff .
cd frontend && npm ci && npm run lint
```

Infrastructure delivery for Auth/Reports/AI is connected directly from GitHub
branch `lab7` to HCP Terraform, with plan review and manual apply. The style
workflow does not deploy. Legacy backend/frontend application releases remain
explicit Make commands.

## Development notes

- The backend bind-mounts `./backend`, so `uvicorn --reload` picks up edits live.
- The frontend runs `next dev` in the container with the same bind mount.
- Backend tests run against a real Postgres (`meetings_test`), truncating tables
  between tests; `make test` creates that database if it is missing.
