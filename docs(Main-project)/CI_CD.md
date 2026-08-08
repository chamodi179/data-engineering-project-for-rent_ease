# CI/CD Pipeline

Two GitHub Actions workflows, plus Dependabot for dependency hygiene.

## `.github/workflows/ci.yml` — runs on every push/PR to `main`/`develop`

Three jobs, all must pass:

1. **api** — `ruff check` (lint), `mypy` (informational only, see below),
   then `pytest` against a real MariaDB service container loaded with the
   actual `docs/01_schema.sql` → `03_procedures.sql` + `05_seed_data.sql`,
   plus `pip-audit` (informational).
2. **frontend** (matrix: `customer`, `admin`) — `next lint`, `tsc --noEmit`,
   `next build`, plus `npm audit` (informational).
3. **docker-build** — builds all three Dockerfiles (api/admin/customer) to
   catch a broken Dockerfile before CD ever tries to push one. Doesn't push
   anywhere; uses the GitHub Actions cache so it stays fast.

**Why mypy and the audit scans are informational (`|| true`) instead of
blocking:** this codebase had zero prior lint/type/audit tooling. `mypy`
currently reports 133 pre-existing type errors (mostly SQLAlchemy `Column[T]`
vs `T` mismatches — real but not urgent) and `npm audit` flags known CVEs in
`next@14.2.15` that only clear with a breaking major-version upgrade. Both
are left visible in the CI log rather than blocking every future PR on
work that's out of scope for the pipeline itself. `ruff` and the actual
test suite (which I ran locally against a real MariaDB before committing
these workflows) **are** blocking, since the codebase is already clean
against them.

## `.github/workflows/cd.yml` — runs after CI succeeds on `main`

1. **gate** — refuses to proceed if the triggering CI run wasn't green.
2. **build-and-push** (matrix) — builds and pushes `api`, `admin`,
   `customer` images to GHCR (`ghcr.io/<owner>/<repo>/<service>`), tagged
   both `:latest` and `:<short-sha>`. Runs Trivy against each image
   (informational — see the npm audit note above).
3. **deploy** — copies `docker-compose.prod.yml` to the production host
   over SSH, pulls the new images, restarts the stack, then polls
   `/health` on both API instances. Only marks the deploy as
   last-known-good (for rollback purposes) once health checks pass.
4. **rollback-on-failure** — if `deploy` fails, redeploys whatever tag was
   last recorded as healthy.

You can also trigger CD manually (`workflow_dispatch`) — useful for
redeploying an older commit without pushing a new one.

## Required GitHub configuration

**Repository secrets** (Settings → Secrets and variables → Actions):

| Secret | Purpose |
|---|---|
| `DEPLOY_HOST` | SSH host/IP of the production server |
| `DEPLOY_USER` | SSH user on that server |
| `DEPLOY_SSH_KEY` | Private key for that user (public key goes in the server's `~/.ssh/authorized_keys`) |
| `GHCR_READ_TOKEN` | A GitHub PAT (or the same deploy user's token) with `read:packages`, used on the server to `docker login ghcr.io` and pull images |

`GITHUB_TOKEN` (used to *push* images from the Actions runner) is provided
automatically — nothing to configure there.

**Repository variables** (same settings page, "Variables" tab):

| Variable | Purpose |
|---|---|
| `CUSTOMER_API_PUBLIC_URL` | e.g. `https://api.rentease.example.com/api/v1` — baked into the customer bundle at build time |
| `ADMIN_API_PUBLIC_URL` | e.g. `https://admin-api.rentease.example.com/api/v1` — baked into the admin bundle at build time |
| `PRODUCTION_URL` | Shown as the environment link on the deploy job in the Actions UI |

**Environment protection:** create a `production` environment (Settings →
Environments) and optionally require manual approval before `deploy` runs —
`cd.yml` already targets `environment: production`, so any protection
rules you add there apply automatically.

## Production host one-time setup

```bash
mkdir -p ~/rentease/backups
# copy .env.production.example to ~/rentease/.env and fill in real values
docker login ghcr.io -u <github-user> -p <GHCR_READ_TOKEN>
```

The host needs Docker + the Compose plugin installed, and the same MySQL
assumption as local dev: a MySQL/MariaDB instance already running and
reachable via `host.docker.internal` (see the NOTE at the top of
`docker-compose.yml`) with the schema from `docs/01_schema.sql` onward
already loaded.

## What's deliberately out of scope here

- **Upgrading `next` past 14.2.15** to clear the CVEs `npm audit` reports —
  it's a breaking change (see `apps/customer`/`apps/admin` build output);
  do this as its own PR once you're ready to test the migration.
- **Making `mypy` blocking** — do this once the 133 pre-existing errors are
  triaged/fixed, not as a side effect of adding CI.
- **A staging environment** — the pipeline as written deploys straight to
  production on merge to `main`. Add a second `deploy-staging` job (same
  shape, different `environment:`/secrets, triggered on `develop`) if you
  want a staging tier between CI and production.
