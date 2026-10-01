# SuccessfulSuccess

## Scope and evidence

SuccessfulSuccess is an existing monorepo for a signed-in user's meetings. Preserve its application, technology stack, database configuration, and CI. Keeping these together provides shared system context and allows API/client changes in one commit.

This document describes the checked-in implementation, based on inspection of source, manifests, lockfiles, Dockerfiles, Compose, migrations, tests, and CI. “Implemented” below means present in those files, not proven by a runtime check during this documentation task. No application, build, dependency installation, tests, or deployment was run.

The earlier proposed Vite application and simplified meeting contract do not apply. AWS deployment will follow separate lecturer instructions later. Existing AWS-related files are inventoried here, but this document provides no deployment procedure and does not establish that any cloud resource exists.

## Repository responsibilities

| Path | Current responsibility |
| --- | --- |
| `backend/` | Python service, dependency manifest/lock, Dockerfiles, startup script, and Alembic configuration. |
| `backend/app/` | FastAPI assembly (`main.py`), settings (`config.py`), async database sessions (`db.py`), Cognito token verification (`auth.py`), shared errors (`errors.py`), optional demo seeding, and Lambda adapter. |
| `backend/app/api/` | HTTP dependencies connecting authentication, database sessions, and services. |
| `backend/app/api/v1/` | `/api/v1` routes for meeting operations and the current user's profile. |
| `backend/app/schemas/` | Pydantic input/output schemas; currently meeting, participant, and user schemas are together in `meeting.py`. |
| `backend/app/models/` | SQLAlchemy mappings for meetings, participants, and users. |
| `backend/app/services/` | Calendar-day rules, meeting use cases, and user profile synchronization. |
| `backend/app/repositories/` | Database queries, owner scoping, persistence, and transaction commits. |
| `backend/alembic/` | Migration environment wired to application settings and ORM metadata. |
| `backend/alembic/versions/` | Revision `0001` creates meetings/participants; `0002` adds users and meeting ownership. |
| `backend/tests/` | Pytest coverage for meeting operations, day windows, ownership, token validation, profiles, and health. Fixtures use PostgreSQL and locally signed test tokens. |
| `frontend/` | Next.js application, TypeScript/tool configuration, package manifest/lock, component configuration, and Dockerfile. There is no Vite or `src/` layout. |
| `frontend/app/` | App Router entry points, root layout, global Tailwind styles, and icon. `/` is the login page. |
| `frontend/app/(app)/` | Route group with an authentication guard; parentheses do not appear in URLs. |
| `frontend/app/(app)/today/` | `/today`: current-day meeting screen. |
| `frontend/app/(app)/meetings/new/` | `/meetings/new`: the same screen with its create dialog initially open. |
| `frontend/components/` | Authentication/provider components, headers/menu, meeting cards/list, participant input, and create/edit, detail, and delete dialogs. |
| `frontend/components/ui/` | Checked-in shadcn/ui component source. |
| `frontend/hooks/` | TanStack Query meeting reads and mutations with cache invalidation. |
| `frontend/lib/` | HTTP client, API TypeScript types, Amplify configuration/token access, datetime formatting, and utilities. |
| `frontend/public/` | Static asset directory, currently containing a placeholder. |
| `.github/workflows/` | Existing `style.yml` runs backend Ruff checks and frontend ESLint on pushes to `main`. |
| `infra/` | Existing AWS templates for authentication, image registry, backend, and frontend, plus a certificate script; preserved for later instructions. |
| Root files | `docker-compose.yml` coordinates local services; `.env.example` lists configuration; `Makefile` contains local and AWS targets; `make.cmd` supports Windows; `README.md` and `SPEC.md` describe the app; `.gitignore`/`.gitattributes` control ignored files and text handling. |

## Existing technology stack and versions

Versions below are values recorded in the repository, not newly selected versions or externally verified release claims. Exact runtime patch versions are not recorded by the floating container tags, and installed versions have not been inspected.

| Component | Checked-in declaration / lock evidence |
| --- | --- |
| Python | `backend/pyproject.toml` requires `>=3.12`; local Dockerfile uses `python:3.12-slim`. |
| FastAPI | Manifest `>=0.115.0`; `backend/uv.lock` records `0.141.1`. |
| SQLAlchemy async ORM | Manifest `>=2.0.30`; lock records `2.0.54`. |
| Alembic | Manifest `>=1.13.0`; lock records `1.20.0`. |
| asyncpg | Manifest `>=0.29.0`; lock records `0.31.0`. |
| Pydantic / pydantic-settings | Manifest `>=2.7.0` / `>=2.3.0`; lock records `2.13.5` / `2.15.0`. |
| Uvicorn | Manifest `>=0.30.0`; lock records `0.53.0`. |
| Authentication / Lambda | Backend uses PyJWT with cryptography and Mangum; frontend uses AWS Amplify (`6.22.0` in its lock). |
| PostgreSQL | Compose uses `postgres:17-alpine`; exact patch version is not pinned. |
| Node.js | Frontend Dockerfile uses `node:22-alpine`; CI selects Node 22. |
| Next.js | Manifest and frontend lock record `16.3.4`. App Router, with standalone output by default. |
| React / React DOM | Both manifest and lock record `19.2.8`. |
| Tailwind CSS | Manifest selects major 4; lock records `4.3.3` for Tailwind and its PostCSS plugin. |
| shadcn/ui / Radix | Component source is committed; `shadcn` lock version is `4.21.0`, `radix-ui` is `1.6.7`. `components.json` selects `radix-nova`, TSX, and RSC support. |
| Frontend forms / data | React Hook Form `7.87.0`, Zod `4.6.1`, TanStack React Query `5.102.8` in the lock; TypeScript `5.9.3`. |
| Tooling | Backend uses uv, pytest, pytest-asyncio, HTTPX, and Ruff; frontend uses npm and ESLint. |

Backend versions and resolutions live in `backend/pyproject.toml` and `backend/uv.lock`. However, the local Dockerfile copies only `pyproject.toml` before running `uv sync`, then copies the rest of the backend. It does not install from the committed lock at that installation step and does not use frozen lock semantics. Its uv image reference uses the floating `latest` tag. Therefore the committed lock is not evidence of the packages actually installed by a fresh backend build. The Lambda Dockerfile likewise installs from the manifest rather than that lock.

Frontend versions and resolutions live in `frontend/package.json` and `frontend/package-lock.json`. Its Dockerfile installs with `npm ci`. Dependency availability, compatibility, clean builds, and resolved runtime versions remain unverified in this task. Existing image references are reported as-is, not changed or replaced with proposed pins.

## Local configuration and startup

The documented local preparation is to copy `.env.example` to the gitignored `.env`, then use `docker compose up --build` from the repository root with Docker Desktop running. `make up-build` wraps that command; `make up` wraps `docker compose up`. Plain Compose can build absent images, but does not guarantee rebuilding existing images after changes. No host Python or Node installation is required for the container path.

Compose has defaults for the local database and ports, so containers can start without an environment-file copy. This does **not** make the authenticated application usable without configuration: the existing frontend and backend require matching Cognito pool/client settings and a valid sign-in. Provisioning those resources is deferred to separate instructions; do not infer their existence from the repository. Optional Google sign-in also needs the configured Cognito OAuth domain and provider setup.

| Configuration | Existing default / use |
| --- | --- |
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | `app`, `app`, `meetings`; local development credentials, not production secrets. |
| `POSTGRES_PORT`, `BACKEND_PORT`, `FRONTEND_PORT` | Laptop ports `5432`, `8000`, `3000`. |
| `DATABASE_URL` | Compose constructs `postgresql+asyncpg://app:app@db:5432/meetings` from database variables; the backend uses this async SQLAlchemy URL. |
| `APP_TIMEZONE` | `Europe/Kyiv`; controls “today,” day boundaries, and meeting timestamp serialization. |
| `CORS_ORIGINS` | `http://localhost:3000`; comma-separated origins. Backend permits credentials, all methods/headers, and exposes `Location`. |
| `LOG_LEVEL` | `INFO`. |
| `RUN_MIGRATIONS_ON_START` | `true`; controls the backend entrypoint's Alembic step. |
| `AWS_REGION` / `COGNITO_REGION` | Compose maps `AWS_REGION`, default `us-east-1`, into backend `COGNITO_REGION`. |
| `COGNITO_USER_POOL_ID`, `COGNITO_CLIENT_ID` | Empty by default; required by backend verification and mapped to frontend `NEXT_PUBLIC_COGNITO_*` variables. |
| `COGNITO_DOMAIN`, `COGNITO_GOOGLE_ENABLED` | Empty / `false`; mapped to public frontend OAuth settings. |
| `NEXT_PUBLIC_API_BASE_URL` | `http://localhost:8000`; browser-facing API URL. |
| `COGNITO_JWKS` | Backend settings can accept signing keys as JSON or base64 JSON; otherwise fetches and caches Cognito keys. Current local Compose does not explicitly pass this setting. |
| `WATCHFILES_FORCE_POLLING`, `WATCHPACK_POLLING` | Compose sets both to `true` for backend/frontend bind-mount file watching. |

`Settings` reads environment variables and an optional `.env` via Pydantic Settings, ignores unrelated keys, validates the timezone, and defaults the API version to `1.0.0`. Root `.env` provides Compose interpolation; Compose explicitly passes its configured values into containers. AWS credentials and deployment variables also appear in `.env.example` for existing scripts; they are not a local database requirement, and no real secret values belong in this document or committed configuration.

### Three existing Compose services

| Service | Internal port | Default laptop port | Dependency and readiness behavior |
| --- | --- | --- | --- |
| `db` | 5432 | 5432 | No service dependency. `pg_isready` checks configured user/database every 5 seconds, timeout 5 seconds, 10 retries. |
| `backend` | 8000 | 8000 | Waits for `db` with `service_healthy`. Own health check uses curl against `/health` every 10 seconds, timeout 5 seconds, 10 retries, start period 20 seconds. |
| `frontend` | 3000 | 3000 | Waits for backend `service_started`, not backend health. No frontend health check is configured. |

The port mappings do not explicitly bind to loopback, so the file does not promise laptop-only access. Services listen on `0.0.0.0` inside containers. PostgreSQL uses named volume `pgdata` at `/var/lib/postgresql/data`; data persists across container recreation and normal `docker compose down`. `docker compose down -v` (also `make down-v`) deletes that data. Initialization variables apply to an empty database volume, not as a password reset on every startup.

Compose builds backend with development dependencies enabled and frontend using its `dev` target. Backend dependencies are installed under `/usr/local`; source is mounted at `/app`. The entrypoint runs `alembic upgrade head` unless disabled, exits on failure, then executes Uvicorn with reload at port 8000. Alembic uses the application's database URL. Frontend starts `next dev` at port 3000, mounts frontend source, and keeps anonymous volumes for `/app/node_modules` and `/app/.next`.

Open `http://localhost:3000` for the login page; API documentation is at `http://localhost:8000/docs`, and public health is at `http://localhost:8000/health`. Frontend startup can precede completed backend migrations/readiness because its dependency gate is only process startup.

### Browser versus container addresses

The browser directly calls `NEXT_PUBLIC_API_BASE_URL` (normally `http://localhost:8000`) with `/api/v1/...` paths and a bearer access token. There is no configured Vite proxy or Next.js API rewrite. These requests cross origins from port 3000 to port 8000 and rely on backend CORS settings. Changing laptop ports requires updating the browser API URL and allowed frontend origin accordingly.

Docker service name `db` is used by the backend at `db:5432`; `backend:8000` is an internal Docker address, not the browser URL. `localhost` inside a container is that container itself. The frontend has no database connection. Public Cognito identifiers and API addresses are browser configuration, not database credentials.

## Existing API contracts

FastAPI registers `/api/v1`. Meeting and profile routes require `Authorization: Bearer <Cognito access token>`. The verifier checks RS256 signatures, issuer, token expiry/required claims, access-token use, and client ID. ID tokens are not accepted as bearer access tokens. The profile sync body separately carries an ID token and verifies that it belongs to the same user.

Every meeting query is scoped to the authenticated user's Cognito `sub`. Accessing another user's meeting behaves as not found. Missing/invalid tokens return 401 when authentication is configured; missing pool/client configuration returns 503. `/health` and generated API documentation are public.

### Meeting input and output

Create and full-replacement update use the same `MeetingCreate` schema:

| Field | Input type, requiredness, and validation |
| --- | --- |
| `name` | Required string, 1–200 characters; surrounding whitespace is stripped and a blank result rejected. Length validation runs before the custom stripping validator. |
| `description` | Optional string or null, default null, maximum 2,000 characters; stripped, with empty text converted to null. |
| `location` | Optional string or null, default null, maximum 200 characters; stripped, with empty text converted to null. |
| `starts_at` | Required datetime; must be timezone-aware. JSON clients send an ISO datetime with `Z` or an explicit offset, e.g. `2026-10-01T10:00:00+03:00`. |
| `ends_at` | Required timezone-aware datetime; strictly later than `starts_at`. |
| `participants` | Optional array, default empty, maximum 50 elements. Each contains required `name` (1–120 characters, stripped and nonblank) and optional `email` (validated email string or null, default null). Duplicate normalized name/email pairs are rejected using case-insensitive comparison. |

There are no API fields called `title` or `attendee_count`. Schemas do not enable strict validation or forbid extra fields: Pydantic's default handling applies, including ignoring unknown object keys rather than rejecting them. Datetime fields are Pydantic datetime values with an awareness validator, not an explicitly string-only parser. No future-only or overlap prohibition is implemented.

A `MeetingRead` JSON object contains exactly these schema fields:

| Field | Output type / meaning |
| --- | --- |
| `id` | Server-generated UUID v4 serialized as a string. |
| `name` | String. |
| `description`, `location` | String or null; keys are present. |
| `starts_at`, `ends_at` | ISO datetime strings serialized in `APP_TIMEZONE`, including its UTC offset. |
| `participants` | Ordered array of objects with `id` (generated UUID string), `name` (string), `email` (string or null), and `position` (integer, zero-based input order). |
| `created_at`, `updated_at` | Generated datetime strings, also serialized in `APP_TIMEZONE`. |

### Meeting endpoints

| Endpoint | Request | Success response |
| --- | --- | --- |
| `GET /api/v1/meetings` | No body. Optional query `date` (`YYYY-MM-DD`, defaults to today in `APP_TIMEZONE`), `q` (string, max 200 characters), `limit` (integer, default 100, range 1–500), and `offset` (integer, default 0, minimum 0). | **200** JSON object with `items` (array of `MeetingRead`), `total` (integer count before pagination), `limit` (integer), `offset` (integer), and `date` (selected calendar date string). Empty results still return this envelope. |
| `GET /api/v1/meetings/{meeting_id}` | UUID path parameter; no body. | **200** `MeetingRead`; **404** for an unknown or differently owned meeting. |
| `POST /api/v1/meetings` | `MeetingCreate` object. | **201** `MeetingRead` after commit; `Location` is `/api/v1/meetings/{id}`. Ensures the owner's database user row exists. |
| `PUT /api/v1/meetings/{meeting_id}` | UUID path parameter and complete `MeetingCreate` object, including required name/times. | **200** `MeetingRead`; replaces all meeting input fields and the participant list. Participants receive new IDs; omitted optional fields take schema defaults. **404** if not owned/found. |
| `DELETE /api/v1/meetings/{meeting_id}` | UUID path parameter; no body. | **204**, no body; removes the meeting and its participants. **404** if not owned/found. |

Listing uses overlap with the half-open day window: meeting start is before the next midnight and meeting end is after the selected midnight. A cross-midnight meeting can appear on both days. Results sort by start time, then name; no unique tie-breaker is specified. Search applies PostgreSQL case-insensitive `LIKE` patterns to name or description using the trimmed query; wildcard characters are not escaped. Unknown query parameters are not explicitly rejected.

### User profile endpoints

`GET /api/v1/me` has no body and returns **200** `UserRead`, creating a bare database user row if necessary. `POST /api/v1/me/sync` requires an object containing `id_token` (nonempty string) and returns **200** `UserRead` after synchronizing validated token profile claims. A token for another user or of the wrong token type returns 401.

`UserRead` has `id` (Cognito subject string), nullable strings `email`, `name`, `given_name`, `family_name`, `picture_url`, boolean `email_verified`, string `auth_provider`, datetime strings `created_at` and `updated_at`, and nullable datetime string `last_login_at`. Unlike meeting timestamps, user timestamps have no custom application-timezone serializer. Synchronization derives profile fields from claims and records login time; ordinary profile reads do not synchronize those claims.

### Errors and health

Registered errors use a top-level `error` object containing `code` (string), `message` (string), and `details` (array). Validation errors return **422**, code `validation_error`, with detail objects containing `field` and `message` strings. Field locations are flattened, e.g. `participants.0.email`; the response message uses the first validation message. This is not FastAPI's default `detail` envelope.

Other registered outcomes include **401** `unauthorized` (with bearer challenge for authentication errors), **404** `not_found`, **503** `service_unavailable`, and **500** `internal_error` with a generic message. Detail arrays are empty unless supplied. Invalid UUID/query/body values are subject to request validation; authentication dependency failures can occur before body errors are returned.

`GET /health` executes database `SELECT 1`. Success is **200** with `status: "ok"`, `database: "ok"`, and `version` (default `"1.0.0"`). Database failure is **503** in the shared error envelope. Health does not validate Cognito setup or test every migrated table, so a healthy backend is not proof of a usable authenticated app.

## Contracts between application parts

**Storage and migrations:** SQLAlchemy maps `meetings`, `participants`, and `users`. Meetings store UUIDs, name, description/location, timezone-aware timestamps, generated created/updated timestamps, and nullable owner reference. Participants reference meetings with database cascade deletion and are ordered by position; ORM replacement uses delete-orphan behavior. Users are keyed by Cognito subject. The database enforces `ends_at > starts_at`. Revision `0002` leaves old meetings with null ownership; owner-scoped queries make those rows invisible. No automatic reassignment is implemented.

**Models versus schemas:** ORM models define persistence, relationships, and constraints. Pydantic schemas define accepted HTTP data and response serialization using ORM attributes. Ownership is assigned from authentication rather than request input and is not exposed in `MeetingRead`. Service code owns day windows and user synchronization; repositories own SQL and commit writes. The session dependency rolls back on exceptions. Production startup uses Alembic, while test fixtures recreate tables from ORM metadata; those tests do not establish migration correctness.

**Frontend and API:** TypeScript shapes in `frontend/lib/types.ts` mirror Pydantic schemas. The fetch client attaches access tokens, parses the shared errors, handles 204 without JSON parsing, and initiates sign-out on 401. Network failures become a client error with status 0. React Query caches meeting lists; successful create/update/delete invalidates all meeting query keys and refreshes active lists. A meeting outside today's window will not appear on the Today screen merely because creation succeeded.

**Frontend behavior and time:** `/` hosts authentication; protected routes redirect signed-out users there. The app implements email/password sign-in, sign-up, email confirmation/resending, and password reset through Cognito, with optional Google OAuth. After loading a signed-in user, the auth provider attempts ID-token profile synchronization once per subject in that provider lifecycle; failures are logged and do not block the page. Authentication events clear cached data to avoid retaining another user's meetings.

The Today page shows list/loading/error/empty states and create, detail, edit, and delete dialogs. The form uses React Hook Form and Zod, creates offset-aware timestamps from the browser's calendar date/time, submits through mutations, closes on success, and displays server validation messages on mapped fields plus a toast on failure. Its single-date form requires end time after start time, so it does not provide the API's cross-midnight input capability. Displayed meeting times are read from API strings in the application timezone rather than converted to browser timezone. The visible count uses returned item count, not the total across pagination; the frontend meeting hook does not expose limit/offset controls.

**CI and existing cloud files:** The style workflow runs only on pushes to `main`, with Ruff `0.16.6` and frontend `npm ci`/ESLint. It does not run application tests or builds. The backend lock records a different Ruff version (`0.16.8`), and the Docker build can resolve another version, so CI/tool parity is not guaranteed. Existing Lambda Dockerfile/adapter, Next.js export stage, infrastructure templates, and AWS Make targets remain preserved; deployment validation and execution await later instructions.

## Implemented versus missing or unverified

Implemented in source/configuration: authenticated owner-scoped meeting CRUD, participant persistence, user profile synchronization, application-timezone day filtering, frontend dialogs/cache updates, automatic local Alembic startup, PostgreSQL persistence, backend health checks, and style CI. Backend tests cover many of these behaviors but were not executed during this task.

The following limitations or verification gaps are visible:

- Fresh-clone containers have database/port defaults, but no configured Cognito pool/client. Complete sign-in and meeting use require external authentication configuration; setup-free offline usage is not implemented.
- Frontend waits for backend process startup rather than readiness and has no Compose health check. Backend health only establishes database connectivity.
- Runtime patch versions are floating; backend builds do not consume the committed lock at installation time. Exact installed packages, clean builds, and compatibility are unverified.
- PostgreSQL and application ports are published without explicit loopback restriction. Local credentials are development defaults.
- No frontend test suite or test/build CI jobs were found. Backend fixtures use ORM-created schemas rather than exercising Alembic upgrades.
- No runtime check confirmed migrations, local startup, Cognito sign-in, Google redirects, browser/API communication, current CI results, or AWS resources. Existing documentation describing something as implemented is not independent execution evidence.
- Some Make targets (`test`, `psql`) hard-code `app` and database names, so changing Compose database credentials does not automatically update those helpers.

This revision replaces the conflicting proposal with the current architecture, contracts, configuration, and startup requirements. Only `PROJECT.md` is updated; deployment remains a separate lab step.
