# SuccessfulSuccess

## Purpose and architectural decision

This document specifies a proposed minimal first slice, not the current implementation. Keep backend, frontend, database configuration, and CI in one repository. API and client changes can be reviewed and committed atomically, and a coding agent can understand the entire system from shared repository context.

The first slice consists of listing and creating meetings through two API endpoints and one frontend page. It has no authentication, users, attendee entities, editing or deleting meetings, Redis, Celery, nginx, Kubernetes, or additional services. AWS, domains, HTTPS, and automated deployment belong to later lab steps; no deployment workflows are designed here.

## Repository inspection and discrepancies

The repository was inspected before writing this document. It already contains an application, migrations, tests, Dockerfiles, dependency lockfiles, documentation, and a style CI workflow. These files remain unchanged.

| Existing contents | Difference from this proposal |
| --- | --- |
| `frontend/app/`, `frontend/next.config.ts`, `frontend/package.json` | Next.js App Router rather than Vite; existing UI includes authentication, dialogs, and multiple routes. Tailwind and shadcn/ui are already present. |
| `backend/app/api/v1/meetings.py`, `backend/app/schemas/meeting.py` | Routes use `/api/v1/meetings`, support additional operations, and list by calendar day with pagination. Schemas use `name`, description, location, participants, and additional timestamps rather than this document's five fields. |
| `backend/app/models/`, `backend/alembic/versions/` | Existing models and migrations include users, ownership, and participant entities. Existing databases are not compatible with the proposed simple meeting schema without a separately reviewed migration plan. |
| `backend/app/auth.py`, frontend authentication modules | Current meeting operations require Cognito configuration and sign-in, conflicting with setup-free local startup. |
| Root `docker-compose.yml` | Already has three services, but the database is called `db`; PostgreSQL is published on the host; frontend uses port 3000 and waits only for backend process startup. Proposed names, ports, and readiness gates differ. |
| Existing Dockerfiles and manifests | Runtime image tags are not patch-pinned; backend uses an unpinned uv image and does not copy its lockfile before dependency installation. Existing dependency versions differ from the proposed baseline below. |
| `infra/`, `backend/Dockerfile.lambda`, `backend/app/lambda_handler.py`, `Makefile`, `make.cmd`, `.env.example` | Existing infrastructure and scripts cover broader AWS, authentication, and deployment concerns outside this first slice. |
| `README.md`, `SPEC.md` | Describe the broader implemented application; README includes copying an environment file and using a build flag. They do not establish the proposed clone-and-start contract. |
| `.github/workflows/style.yml` | Existing lint/format CI is already colocated with the application. Preserve it; future CI also belongs here, without designing deployment. |

This proposal does not claim that the current checkout satisfies its startup or API contracts. Reconciling it with the existing application requires a later implementation task.

## Minimal proposed structure

| Folder or root file | Responsibility |
| --- | --- |
| `backend/` | Python service boundary; owns its Dockerfile, startup entrypoint, `pyproject.toml`, `uv.lock`, and `alembic.ini`. |
| `backend/app/` | FastAPI application assembly, configuration, database engine/session lifecycle, and HTTP readiness endpoint. |
| `backend/app/api/` | Only meeting list/create HTTP handlers; validate input, transact through SQLAlchemy, and serialize API schemas. No additional service or repository layer is necessary for this slice. |
| `backend/app/models/` | SQLAlchemy database mappings and database constraints. |
| `backend/app/schemas/` | Separate Pydantic request and response schemas defining the public contract. |
| `backend/alembic/` | Alembic environment that uses the backend database configuration and ORM metadata. |
| `backend/alembic/versions/` | Committed, ordered schema migrations; creates the meetings table. |
| `backend/tests/` | Focused API, validation, persistence, and migration checks for this contract. |
| `frontend/` | React + Vite service boundary; owns its Dockerfile, Vite configuration, HTML entry point, `package.json`, `package-lock.json`, and shadcn component configuration. |
| `frontend/src/` | One meeting page, application entry point, and Tailwind stylesheet. |
| `frontend/src/components/` | Meeting list and add-meeting form components. |
| `frontend/src/components/ui/` | Committed shadcn/ui component source needed by that page; no unrelated component collection. |
| `frontend/src/lib/` | HTTP client, API field types, date conversion, and component utilities. |
| `.github/` | Repository automation configuration. |
| `.github/workflows/` | Existing and future CI configuration; deployment design is deferred. |
| `docker-compose.yml` | Exactly three services: `postgres`, `backend`, `frontend`; local environment defaults, builds, network, readiness dependencies, and named database volume. Database configuration stays here, so no separate database folder is needed. |
| `PROJECT.md` | This proposed architecture and the contracts between its parts. |

The repository root is the integration boundary, not another application. Existing files and folders outside this proposed structure remain as documented discrepancies.

## Runtime and dependency baseline

These are concrete compatible baseline selections, not claims to be the newest releases. Release availability was checked against the linked primary sources. Full dependency resolution and exact container tag availability have not been exercised in this documentation-only task.

| Component | Proposed version | Evidence / compatibility |
| --- | --- | --- |
| Python | 3.12.10 | [Python release](https://www.python.org/downloads/release/python-31210/); runtime for the backend. |
| FastAPI | 0.115.12 | [PyPI release](https://pypi.org/project/fastapi/0.115.12/); supports Python 3.12 and Pydantic 2. |
| SQLAlchemy ORM | 2.0.40 | [PyPI release](https://pypi.org/project/SQLAlchemy/2.0.40/); asynchronous ORM sessions. |
| Alembic | 1.15.2 | [PyPI release](https://pypi.org/project/alembic/1.15.2/); compatible with SQLAlchemy 2. |
| Pydantic | 2.11.3 | [PyPI release](https://pypi.org/project/pydantic/2.11.3/); API validation and serialization. |
| Uvicorn | 0.34.2 | [PyPI release](https://pypi.org/project/uvicorn/0.34.2/); FastAPI ASGI server. |
| asyncpg | 0.30.0 | [PyPI release](https://pypi.org/project/asyncpg/0.30.0/); PostgreSQL driver for Python 3.12. |
| uv | 0.6.14 | [PyPI release](https://pypi.org/project/uv/0.6.14/); backend dependency locking and installation. |
| PostgreSQL | 17.4 | [PostgreSQL release](https://www.postgresql.org/docs/release/17.4/); supported by the chosen driver. |
| Node.js | 22.14.0 | [Node release](https://nodejs.org/en/blog/release/v22.14.0); satisfies Vite 6's Node 22 support. |
| React and React DOM | 19.0.0, both | [React 19 release](https://react.dev/blog/2024/12/05/react-19); keep both package versions identical. |
| Vite | 6.3.5 | [Versioned package metadata](https://raw.githubusercontent.com/vitejs/vite/v6.3.5/packages/vite/package.json); compatible with Node 22. |
| Vite React plugin | 4.4.1 | [Versioned package metadata](https://raw.githubusercontent.com/vitejs/vite-plugin-react/plugin-react%404.4.1/packages/plugin-react/package.json); declares Vite 6 compatibility. |
| Tailwind CSS and `@tailwindcss/vite` | 4.0.0, both | [Tailwind 4 release](https://tailwindcss.com/blog/tailwindcss-v4), [plugin metadata](https://raw.githubusercontent.com/tailwindlabs/tailwindcss/v4.0.0/packages/@tailwindcss-vite/package.json). |
| shadcn/ui | Committed React 19 / Tailwind 4 component source | [Official compatibility guidance](https://ui.shadcn.com/docs/tailwind-v4). This is copied component source, not a versioned runtime framework. A concrete CLI/registry revision remains **unverified and must be selected and verified before implementation**; no CLI version is invented here. |

Record exact backend dependency pins in `backend/pyproject.toml` and the complete resolution in `backend/uv.lock`; install with frozen lockfile semantics during image build. Record exact frontend pins in `frontend/package.json` and all transitive packages in `frontend/package-lock.json`; build with `npm ci`. Record runtime versions in the respective Dockerfiles and PostgreSQL's version in root Compose. Pin uv explicitly in the backend build. Record the verified shadcn generator version and registry provenance in `frontend/components.json` or its adjacent documentation, and commit the generated component source; lock all of its runtime dependencies in the frontend lockfile.

Proposed image tags are `python:3.12.10-slim-bookworm`, `node:22.14.0-bookworm-slim`, and `postgres:17.4-bookworm`. Their registry availability and supported laptop architectures require verification before implementation. Do not replace these with floating tags. The lockfiles must be reconciled with the chosen baseline in a later task, not reused unchanged on the assumption that they already match.

## One-command local startup

After cloning and starting Docker Desktop, the developer runs `docker compose up` from the repository root. No host Python or Node installation, environment-file copying, database creation command, migration command, seed command, or cloud credentials are required. Docker Desktop supplies Compose; initial image downloads and locked dependency installation require network access. The baseline assumes the laptop ports below are free.

1. Compose pulls the pinned PostgreSQL image and builds backend/frontend images from their respective Dockerfiles when images are absent. Image builds install the committed locked dependencies inside containers. Plain `docker compose up` does not promise to rebuild an already-built image after later source or dependency changes; that is outside the fresh-clone guarantee.
2. PostgreSQL initializes the configured database and local role on an empty named volume. Its health check runs `pg_isready` against that role and database. Backend depends on PostgreSQL with `service_healthy`, not merely process startup.
3. The backend entrypoint runs `alembic upgrade head` using the same database URL as the application. It must exit on migration failure and start Uvicorn only after migrations succeed. Repeating startup applies only outstanding migrations; ORM table auto-creation is not a substitute for Alembic.
4. Uvicorn listens on all container interfaces at port 8000. Backend readiness is checked at `/health` using an HTTP client included in the image; the endpoint returns HTTP 200 with a JSON object containing only `status` equal to `ok` when a database `SELECT 1` succeeds, otherwise HTTP 503. This operational endpoint is separate from the two meeting endpoints.
5. Frontend depends on backend with `service_healthy`. Vite listens on all container interfaces at port 5173, with strict port selection. Once ready, the developer opens `http://localhost:5173` and sees the page, initially with an empty meeting list.

Readiness checks should have explicit intervals, timeouts, retries, and initialization grace periods, allowing a normal first startup without hiding failures indefinitely. Use a 5-second interval, 5-second timeout, 30 retries, and a 30-second start period as local defaults. Logs must expose migration or readiness failures. No fourth migration service is introduced.

### Compose services

| Service | Internal listening port | Laptop exposure | Dependencies | Dependency readiness / own readiness |
| --- | --- | --- | --- | --- |
| `postgres` | 5432 | None | None | Own health check: `pg_isready` for the configured database and role. |
| `backend` | 8000 | `127.0.0.1:8000` mapped to 8000 | `postgres` | Wait for PostgreSQL `service_healthy`; run migrations before listening; own `/health` checks database connectivity. |
| `frontend` | 5173 | `127.0.0.1:5173` mapped to 5173 | `backend` | Wait for backend `service_healthy`; own HTTP probe of `/` on port 5173 using the container's Node runtime confirms Vite serves the page. |

Use a named volume `pgdata` mounted at `/var/lib/postgresql/data` for PostgreSQL 17. Data survives container replacement, normal shutdown, and `docker compose down`. Explicit volume deletion, such as `docker compose down -v`, deletes local meetings; startup must never delete the volume automatically. Changing initialization credentials later does not reinitialize a populated volume.

### Local defaults and address contract

Compose provides literal development-only defaults: database `successfulsuccess`, user `successfulsuccess_dev`, and password `local_dev_only`. These are disposable local credentials, never production credentials. The backend connection URL is `postgresql+asyncpg://successfulsuccess_dev:local_dev_only@postgres:5432/successfulsuccess`. Database access remains on the Compose network; only loopback host ports are published. Do not place database credentials or connection URLs in browser-delivered environment variables.

The browser loads the page at `http://localhost:5173` and calls relative `/api/meetings` URLs. Vite's local development proxy forwards `/api` unchanged to `http://backend:8000`. `backend` and `postgres` are Docker DNS service names usable by containers, not by the developer's browser. Container `localhost` refers to that same container, not the laptop or another service.

The laptop can reach the backend directly at `http://localhost:8000` for API inspection. The frontend's browser requests use the Vite origin and proxy, so no cross-origin browser configuration is required for this page. Neither direct browser calls to `http://backend:8000` nor frontend connections to PostgreSQL are allowed by this architecture.

## Meeting and API contract

All request and response bodies use JSON, with `application/json` content type. The public routes are exactly `/api/meetings` without a `/v1` segment. No authentication header is required.

### Fields

| Field | API type | Create request | Read response | Validation / meaning |
| --- | --- | --- | --- | --- |
| `id` | UUID string | Must be absent | Required | Server generates a UUID v4 for each successfully created meeting; returned in canonical hyphenated form. |
| `title` | String | Required | Required | Trim surrounding whitespace, then require 1–200 characters; reject blank strings. Return the normalized title. |
| `starts_at` | RFC 3339 datetime string | Required | Required | Must contain a time and explicit UTC offset or `Z`, e.g. `2026-10-01T09:00:00Z` or `2026-10-01T12:00:00+03:00`; timezone-naive strings and numeric timestamps are invalid. |
| `ends_at` | RFC 3339 datetime string | Required | Required | Same format; must be strictly later than `starts_at` when compared as instants. |
| `attendee_count` | JSON integer | Required | Required | From 0 through 2,147,483,647, matching PostgreSQL's integer range; reject booleans, fractional numbers, and numeric strings. It is a count only, with no attendee records. |

All five read fields are non-null. All four create fields are non-null and have no defaults. Reject unknown create fields, including a client-supplied `id`. Do not coerce strings into integers or numbers into titles. Accept valid timestamps in the past; there is no future-only rule or overlap restriction. Normalize stored instants and response timestamps to UTC; responses use `Z` and preserve fractional seconds when present, to at most microsecond precision. Local datetime form inputs must be converted to offset-aware strings before submission; the page displays instants in the browser's local timezone.

### Exact endpoint shapes

| Endpoint | Request | Success response |
| --- | --- | --- |
| `GET /api/meetings` | No body; no supported filters or pagination parameters. | HTTP **200 OK**. Top-level JSON array of meeting objects. Each object has exactly `id`, `title`, `starts_at`, `ends_at`, `attendee_count`, with the types above. Return all meetings ordered by `starts_at` ascending and then `id` ascending for ties. An empty database returns an empty array. No envelope or metadata. |
| `POST /api/meetings` | One top-level JSON object containing exactly `title`, `starts_at`, `ends_at`, `attendee_count`. | HTTP **201 Created** only after the database transaction commits. One top-level meeting object containing exactly the five read fields, including the server-generated `id` and normalized values. No response envelope. |

Unknown query parameters on the list endpoint are rejected with HTTP 422 rather than silently enabling a broader API. There is no individual-meeting read route in this slice, so no `Location` header pointing to an unimplemented route is required. Duplicate payloads create separate meetings; there is no deduplication or idempotency contract.

### Validation errors

Malformed JSON, missing required data, wrong field types, nulls, extra fields, invalid timestamps, invalid count ranges, or invalid time ordering return HTTP **422 Unprocessable Entity** and create no row. Define a normalized FastAPI-style error body with exactly one top-level key, `detail`, containing a nonempty array of error objects:

| Error object field | Type | Meaning |
| --- | --- | --- |
| `loc` | Array of strings and/or integers | Error location: typically `body` followed by a field name, or `query` followed by an unsupported parameter; malformed JSON can use `body` followed by a character offset. |
| `msg` | String | Human-readable validation explanation. Wording is not a client parsing contract. |
| `type` | String | Machine-readable validation category, such as `missing`, `string_type`, `int_type`, `extra_forbidden`, `json_invalid`, or `value_error`. |

Normalize framework validation errors to those three keys; do not return raw inputs, exception context, or internal database details. Attach invalid time ordering to `ends_at`. The frontend uses locations to display field errors and a general message for body-level errors. Server or database failures are unsuccessful responses, never a fabricated 201; show a general failure and keep the form values.

## Contracts between the parts

**Database and backend:** PostgreSQL owns persisted meeting rows. The SQLAlchemy meeting model maps a UUID primary key, a non-null title of up to 200 characters, two non-null timezone-aware timestamp columns (`TIMESTAMP WITH TIME ZONE`), and a non-null integer count. Database check constraints enforce a positive interval, a nonblank title, and a nonnegative count. PostgreSQL stores instants rather than the original timezone name. Alembic owns schema evolution; application startup owns applying committed migrations. Each create operation uses one transaction; a failed transaction rolls back.

**Database models and API schemas:** SQLAlchemy models describe storage, constraints, and ORM behavior; Pydantic schemas describe allowed request fields and serialized response fields. Use separate create and read schemas. Never expose an ORM instance as an uncontrolled JSON dictionary or accept all database columns as input. API validation provides useful 422 responses before persistence, while database constraints protect stored data independently. The backend's OpenAPI description must agree with the tables above.

**Backend and frontend:** Only the HTTP JSON contract connects them. Frontend API types mirror those schemas; frontend code imports no Python models and has no direct database access. The page loads the list on entry, displays all five fields, and provides a form for the four create fields. During submission, prevent duplicate clicks. After a successful 201, clear the form and refetch `GET /api/meetings` to update the list in server order. If the refetch fails, report that creation succeeded but refreshing failed and allow retrying the list fetch; do not resubmit the already successful POST. Validation and network failures preserve form values and do not imply creation succeeded.

**Compose and applications:** Compose supplies internal URLs and local defaults, installs dependencies through builds, sequences readiness, and provides durable database storage. Applications must fail visibly on missing connectivity or migration errors. No external account or preexisting cloud resource is part of local startup.

**CI and repository:** Keep future CI alongside the applications so checks can use the same dependency manifests, lockfiles, and API contract. Existing CI is preserved. No new CI jobs, deployment pipelines, or infrastructure are specified or implemented by this document.

## Assumptions requiring review

- Approve the proposed contract over the existing Next.js, authenticated, day-filtered application; any conversion or existing-data migration needs a separate task.
- Confirm UUID v4 identifiers, title length 200, nonnegative integer counts including zero, UTC response normalization, and an unpaginated all-meetings list are appropriate for the first slice.
- Confirm browser-local timezone display and the proxy-based browser address contract, including loopback ports 5173 and 8000.
- Before implementation, verify exact Docker image tags and target architectures, resolve and validate the dependency locks, and select a verified shadcn CLI/registry revision compatible with React 19 and Tailwind 4. The documented baseline is release-verified where linked, but has not been integration-tested here.

This document records the monorepo decision, minimal folder responsibilities, API and persistence contracts, concrete dependency baseline, three-service local startup behavior, and discrepancies with the current checkout. It changes documentation only.
