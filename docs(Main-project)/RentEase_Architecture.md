# RentEase — System Architecture (Customer Site + Admin Dashboard, Separated)

> **Last updated 2026-08-02** — covers the as-built system through the realtime (WebSocket/Redis pub-sub) layer, Celery beat scheduled tasks, and the two-tier cancellation/refund policy (§§7a, 7b).

## 0. Architecture classification (used architecture)

**This is a modular monolith backend, deployed as two isolated runtime instances, behind two separate frontend apps. It is not microservices.**

| | This architecture | Microservices |
|---|---|---|
| Codebase | 1 (`apps/api`) | Many, one per service |
| Database | 1 shared MySQL | Typically 1 per service |
| Deployed processes | 2 (`api-public`, `api-admin`) — same code, different mount | Many, independently deployed |
| Communication | In-process function calls within each instance | Network calls / messaging between services |
| Failure isolation | Per-instance (public traffic can't crash admin's instance) | Per-service |
| Why this, not microservices | Booking/payment/document creation touches multiple tables in one transaction — splitting them into services would mean distributed transactions for basic writes, with no team-scaling or independent-release benefit at MVP size | Justified once a specific capability (e.g. payments) needs independent scaling, its own team, or its own release cycle |

The two-instance split (Section 4) gets you real failure isolation between customer and admin traffic — the actual goal — without taking on distributed-systems costs (service discovery, network retries, eventual consistency, distributed tracing) that microservices would require. If a specific piece (e.g. payments) ever outgrows this, the code is already namespaced by domain (`routers/public`, `routers/admin`, `services/`), so it can be peeled out into its own service later without a rewrite.

---

## 1. Why separate the two frontends

The MVP spec left the door open to running admin as "a second set of routes in the same Next.js app." For a real build, splitting them is the better call:

| Concern | Shared app | Separate apps |
|---|---|---|
| Bundle size | Customers download admin JS they'll never use | Each app ships only what it needs |
| Security blast radius | One XSS/auth bug exposes both surfaces | Admin is isolated from public traffic |
| Deploy cadence | A risky admin feature blocks a customer hotfix | Deploy independently |
| Auth model | Must awkwardly support two token types in one app | Each app has one clean auth flow |
| Team scaling | Hard to hand admin to a different dev/agency later | Clean ownership boundary |

Given RentEase already leans FastAPI + Next.js, the cleanest way to get this split without duplicating logic is a **monorepo with two Next.js apps, backed by one FastAPI codebase deployed as two isolated runtime instances** (Section 4).

---

## 2. High-level topology

```
                                       ┌─────────────────────────┐
                                       │        Stripe            │
                                       └───────────▲──────────────┘
                                                   │ webhooks
┌────────────────┐   HTTPS   ┌────────────────────┴──┐
│  Customer App    │ ───────▶ │  api-public (instance) │──┐
│  app.rentease.com│          │  same code as api-admin│  │
│  (Next.js)       │          │  mounts /public/* only │  │
└────────────────┘          └────────────────────────┘  │   SQL   ┌──────────────┐
                                                            ├──────▶│  MySQL        │
┌────────────────┐          ┌────────────────────────┐  │         └──────────────┘
│  Admin App       │ ───────▶ │  api-admin (instance)   │──┘   ┌──────────────┐
│  admin.rentease. │          │  same code as api-public│─────▶│  Redis        │
│  com (Next.js)   │          │  mounts /admin/* only   │      └──────────────┘
└────────────────┘          └───────────┬────────────┘      ┌──────────────┐
                                          │ enqueue           ──────────────▶│  MinIO/S3     │
                                          ▼                                  └──────────────┘
                                  ┌──────────────┐
                                  │ Celery worker │  (emails, receipts, thumbnails)
                                  └──────────────┘
```

**Same codebase, two isolated processes.** `api-public` and `api-admin` are literally the same FastAPI app (`apps/api`) deployed twice, each started with a different env var that controls which router group it mounts. No code duplication, no separate services to maintain — but a crash, traffic spike, or bad deploy on the customer-facing instance never touches the admin instance, because they're different processes with their own memory and their own DB connection pool. Both still talk to the one shared MySQL database — see Section 0 for why that's the right boundary to keep shared and where the process boundary is worth paying for.

---

## 3. Repository layout (as actually built — no monorepo tooling)

> **Correction (2026-07):** earlier drafts of this document described this
> as a pnpm + Turborepo monorepo with shared `packages/api-client` and
> `packages/ui`. That tooling was never actually built — there's no
> `pnpm-workspace.yaml`, no `turbo.json`, and no `packages/` directory in
> the delivered project. What exists is simpler: one Git repo holding
> three independently-managed apps, each with its own `npm`
> `package.json` / `package-lock.json`. This section now describes that
> reality instead of the original plan.

```
rentease/
├── apps/
│   ├── customer/               # Next.js — public site + customer account (own package.json)
│   ├── admin/                  # Next.js — staff/super_admin dashboard (own package.json)
│   └── api/                    # FastAPI — single backend, both apps call it
├── docs/                       # architecture, spec, SQL schema/triggers/procedures/seed data
├── docker-compose.yml
└── README.md
```

- **One Git repo, not a tooled monorepo.** `apps/customer` and `apps/admin` are two ordinary Next.js projects that happen to live side by side. Each is installed and built independently (`cd apps/customer && npm install`, same for `apps/admin`) — there's no root-level install step, no workspace-wide `npm run build`, and no single lockfile shared between them.
- **No shared `packages/` directory.** There is no generated API client, no shared UI-component package, and no shared eslint/tsconfig/tailwind config package. Each app defines its own `tsconfig.json`, `tailwind.config.ts`, and calls the API with a small hand-written `fetch` wrapper (`lib/api.ts` in each app) rather than a generated, typed client.
- **Practical effect of not having this tooling:** type drift between the two frontends and the FastAPI schemas is possible and is not caught automatically — if `schemas/common.py` changes a field, nothing fails a build in `apps/customer` or `apps/admin` until it's manually updated and tested. At the project's current size (two frontends, one backend, a handful of shared shapes like `User`/`Booking`/`Payment`) this is a deliberate, acceptable tradeoff rather than an oversight: setting up `pnpm` workspaces + Turborepo + a generated OpenAPI client is real ongoing maintenance for a benefit that only pays off once the number of shared types or the team size grows. If that happens, Section 3's original plan (`packages/api-client` generated from `/openapi.json`, a shared `packages/ui`) is still the right next step — it just hasn't been built yet.
- `docker-compose.yml` at the repo root is what actually ties the three apps together for local/dev use — see the root `README.md` for how to run everything.

---

## 4. Backend: one codebase, two deployed instances

```
apps/api/
├── main.py                    # reads APP_MODE env var, mounts routers accordingly
├── core/
│   ├── config.py              # APP_MODE: "public" | "admin"
│   ├── security.py          # JWT issue/verify, password hashing
│   └── deps.py              # get_current_user, require_role()
├── routers/
│   ├── public/               # mounted only when APP_MODE=public
│   │   ├── items.py          # browse, availability search
│   │   ├── bookings.py       # create booking, my bookings
│   │   ├── auth.py           # customer login/register
│   │   └── payments.py       # Stripe checkout session
│   └── admin/                 # mounted only when APP_MODE=admin
│       ├── items.py           # CRUD inventory
│       ├── bookings.py        # list/filter, status change
│       ├── customers.py       # customer list, document review
│       ├── payments.py        # manual payment recording
│       └── staff.py           # staff account management
├── models/                    # SQLAlchemy models (shared by both instances)
├── schemas/                   # Pydantic schemas, split public/ and admin/
└── services/                  # business logic: availability check, pricing, booking state machine
```

```python
# main.py
app = FastAPI()

if settings.APP_MODE == "public":
    app.include_router(public_router, prefix="/api/v1")
elif settings.APP_MODE == "admin":
    app.include_router(admin_router, prefix="/api/v1")
```

Each running instance only ever loads *one* router group into memory — an `api-public` process has no admin routes registered at all, not even behind a permission check, so there's nothing for public traffic to accidentally hit. **Models and services are shared** (one `bookings` table, one availability-check function, imported by whichever instance needs them) but **routers and schemas are split** by audience, and now so is the running process itself. This avoids duplicating business logic while still giving each surface its own request/response contracts, permission checks, and — critically — its own failure domain.

### RBAC enforcement — three layers now, not two

1. **Process-level isolation**: the `api-public` instance has zero admin routes registered (Section 4) — this isn't a permission check, it's the absence of a route to even attack.
2. **Router-level dependency**: within `api-admin`, every route requires `require_role(["staff", "super_admin"])`. Within `api-public`, every route with side effects (create booking, cancel) requires `require_role(["customer"])`.
3. **Row-level checks in services**: e.g. a customer fetching booking detail must also own that `customer_id` — role alone isn't enough, since `require_role` doesn't know *whose* booking it is.

```python
# core/deps.py
def require_role(allowed: list[str]):
    def checker(user: User = Depends(get_current_user)):
        if user.role not in allowed:
            raise HTTPException(403, "Forbidden")
        return user
    return checker
```

---

## 5. Auth: separate flows, same mechanism

Both apps use JWT access + refresh tokens in **httpOnly, Secure cookies** (not localStorage — avoids XSS token theft). The mechanism is identical; the *flows* differ:

| | Customer app | Admin app |
|---|---|---|
| Login endpoint | `/public/auth/login` | `/admin/auth/login` |
| Who can obtain a token | `role = customer` | `role = staff, super_admin` |
| Token cookie domain | `app.rentease.com` | `admin.rentease.com` |
| Session length | Longer (7d refresh) | Shorter (8h refresh) — admin sessions should expire faster |

Because the cookies are scoped to different subdomains, a customer session cookie is never even sent to the admin app — that's a free extra layer of isolation on top of the role check.

**Account lockout.** Both login endpoints (`/public/auth/login`, `/admin/auth/login`) share the same brute-force protection: `users.failed_login_attempts` increments on each wrong password, and once it reaches `settings.MAX_LOGIN_ATTEMPTS` (default 5), `users.locked_until` is set `settings.LOCKOUT_MINUTES` (default 15) into the future. A locked account is rejected — with a "try again in N minutes" message — even if the very next attempt has the correct password. Any successful login resets both counters to zero. This applies per-account, not per-IP; it is deliberately simple (no CAPTCHA, no IP-based rate limiting) to match MVP scope, and is the right layer to extend first if abuse shows up in practice.

**Password policy.** `RegisterIn` (customer registration) and `StaffCreateIn` (staff/super_admin creation) both validate the password server-side via `validate_password_strength()` in `core/security.py`: minimum 8 characters, at least one letter, at least one digit, and rejection of a short list of common passwords. Both frontends mirror this check client-side for faster feedback, but the server is the source of truth — a request that skips the frontend (e.g. a direct API call) still gets validated.

---

## 6. Frontend structure

### `apps/customer` (Next.js App Router)

```
app/
├── (public)/
│   ├── page.tsx                # home / browse
│   ├── items/[id]/page.tsx     # item detail + availability calendar
│   └── search/page.tsx
├── (auth)/login, register
├── (account)/                  # requires customer auth
│   ├── bookings/page.tsx       # My Bookings
│   ├── bookings/[id]/page.tsx
│   └── checkout/page.tsx       # date select → price review → Stripe (no document-upload step)
└── layout.tsx
```

- Mobile-first (per spec §6) — build with Tailwind, test at 375px width first.
- Server Components for browse/search (SEO matters for a public site); Client Components + TanStack Query for anything interactive post-login (My Bookings, checkout).

### `apps/admin` (Next.js App Router)

```
app/
├── (dashboard)/
│   ├── page.tsx                 # today's pickups/returns, active rentals
│   ├── inventory/page.tsx       # item CRUD
│   ├── bookings/page.tsx        # filterable list
│   ├── bookings/[id]/page.tsx   # detail + status change
│   ├── customers/page.tsx       # list + search (no ID document review — see §7)
│   ├── payments/page.tsx        # transaction list (all staff) + manual entry (super_admin only)
│   └── staff/page.tsx           # super_admin only
└── layout.tsx                   # sidebar nav, auth guard
```

- No SEO concerns → everything can be a Client Component behind auth; optimize for data density (tables, filters) over marketing polish.
- Middleware (`middleware.ts`) checks the session cookie and role on every route — redirect to admin login if missing, 403 page if role is `customer` (shouldn't happen given separate cookie domains, but defense in depth).

---

## 7. Cross-cutting concerns

- **Shared types**: there is no generated shared client (see Section 3's correction) — each frontend hand-writes its own `lib/types.ts` matching the relevant Pydantic schemas. Keeping these in sync across `apps/customer`, `apps/admin`, and `apps/api/app/schemas` is a manual discipline, not an enforced one.
- **File uploads** (item-catalog photos): the admin app requests a **presigned MinIO/S3 URL** from the API, then uploads directly from the browser. The API never proxies file bytes. There is no customer-facing ID/document upload step — that workflow (a blocking "upload ID before payment" step in checkout, plus an admin document-review screen) was removed; the `documents` table, its API routes, and the review UI no longer exist. Booking creation and payment only ever require account login, not identity-document review.
- **Background jobs**: booking confirmation emails, receipt generation — enqueued to Celery from the API, processed by a worker container. Neither frontend talks to Celery directly.
- **Stripe**: customer app creates a Checkout Session via the API; Stripe webhook hits the API directly (`/public/payments/webhook`), which updates `payments`/`bookings` — never trust the frontend to confirm payment success.
- **Manual payments/refunds**: recording a manual (cash/bank-transfer) payment or refund (`POST /admin/payments`) is restricted to `super_admin` only — regular `staff` can view the payments ledger (`GET /admin/payments`) but cannot create entries in it, since a manual entry bypasses Stripe and is trusted at face value. Enforced both in the API (`require_role(["super_admin"])`) and in the admin frontend (the "Record manual payment" form only renders for a signed-in `super_admin`).
- **Cancellation/refund policy is two-tier**: a customer cancelling within the cooling-off window gets an automatic refund via `cancel_booking()`; a staff/`super_admin` cancellation outside that window follows the separate staff cancel policy and may require a manual refund entry. Both paths write to `booking_status_history` and the shared `audit_logs` table, and both publish a booking event (Section 7a) so the admin dashboard reflects the change without a reload.

---

## 7a. Realtime updates: Redis pub/sub + WebSocket (added post-MVP)

The admin dashboard originally required a manual page reload to see another admin's — or a customer's, or a webhook's — change land. That's now live-refreshed:

```
booking created/cancelled/confirmed/etc.
        │  (booking_service.py, after DB commit)
        ▼
publish_booking_event()  ──▶  Redis PUBLISH  "admin:bookings"
                                      │
                                      ▼
                        GET /admin/ws/bookings  (WebSocket, api-admin only)
                                      │
                                      ▼
                     admin-web: useBookingEvents() hook ──▶ re-fetch affected list/detail
```

- **Publisher** (`app/services/realtime.py`): a thin wrapper around `redis.Redis.publish()` on a single channel (`admin:bookings`). Called from `booking_service.py` right after a booking is created or its status changes. Deliberately **best-effort** — Redis errors are swallowed, never raised — because the booking's DB row is already committed by the time this runs; a Redis hiccup should never fail a request or roll back a real state change over what's purely a UX nicety.
- **Subscriber** (`app/routers/admin/realtime.py`): a WebSocket endpoint (`/admin/ws/bookings`), mounted only on `api-admin` (never `api-public` — customers have no reason to see this feed, and the route doesn't even exist in that process, same "absence of a route" isolation as Section 4's RBAC layer 1). Auth is done by hand against the same namespaced admin access-token cookie the HTTP routes use, since FastAPI's `Depends()`-based cookie/role dependencies are built for request/response, not the websocket handshake. Each connected client gets its own `redis.asyncio` pub/sub subscription and just relays messages straight through to the browser.
- **Payload is intentionally thin**: `{event, booking_id, booking_reference, status}` — a "something changed, go re-fetch it" signal, not a full booking object. The admin frontend still re-fetches from the API on receipt, so the WebSocket message never needs to be treated as a source of truth; if a message is ever dropped, the next manual reload (or the next event) shows the correct state regardless.
- **Consumers**: the admin `useBookingEvents()` hook drives live-refresh on the bookings list, the booking detail page, and the payments ledger (Section 6's `apps/admin` tree).

## 7b. Scheduled tasks: Celery beat

A second Celery process type was added alongside the existing worker — **`beat`**, a scheduler that enqueues tasks on a timer rather than processing them itself:

```yaml
# docker-compose.yml
beat:
  build: ./apps/api
  command: celery -A app.worker beat --loglevel=info
```

Currently it drives one job: `expire_stale_pending_bookings`, enqueued every 15 minutes, which cancels any booking still `pending` more than `PENDING_EXPIRY_HOURS` (24h) after creation — freeing the reserved inventory instead of holding it indefinitely on an abandoned checkout. The task itself still runs on the regular `worker` container; `beat` only ever schedules, it never executes application code, so losing/restarting the `beat` container just delays the next enqueue rather than risking a duplicate cancellation.

---

## 8. Deployment (Docker Compose, single VM — matches MVP scope)

Both API services build from the **same Dockerfile / same `apps/api` code** — they differ only by the `APP_MODE` env var, which controls which routers get mounted (Section 4) and gives each its own connection pool size:

```yaml
services:
  api-public:
    build: ./apps/api
    environment:
      - APP_MODE=public
      - DB_POOL_SIZE=20        # sized for higher customer traffic
    env_file: .env

  api-admin:
    build: ./apps/api          # same image as api-public
    environment:
      - APP_MODE=admin
      - DB_POOL_SIZE=10        # smaller — admin traffic is low volume
    env_file: .env

  customer-web:
    build: ./apps/customer
    environment:
      - API_URL=http://api-public:8000
    depends_on: [api-public]

  admin-web:
    build: ./apps/admin
    environment:
      - API_URL=http://api-admin:8000
    depends_on: [api-admin]

  worker:
    build: ./apps/api
    command: celery -A app.worker worker

  beat:
    build: ./apps/api          # same image as worker — scheduler only, see §7b
    command: celery -A app.worker beat --loglevel=info

  mysql:
    image: mysql:8.0
  redis:
    image: redis:7             # now also the pub/sub broker for §7a's live-refresh, not just the Celery broker
  minio:
    image: minio/minio
```

> **Note:** the snippet above is illustrative of a general production VM deploy. Two real, separate compose files now exist in the delivered project:
> - `docker-compose.yml` — local/dev. The database runs on the host machine rather than in a container, so there's no `mysql:` service defined there at all; `api-public` and `api-admin` reach it via `host.docker.internal`. This is also where the `beat` service (§7b) actually lives.
> - `docker-compose.prod.yml` — production, pulling pre-built images from GHCR (see `docs/CI_CD.md` for the pipeline that builds and pushes them) rather than building from source on the VM.
>
> See the project's `README.md` for the real setup and which file to use when.

Reverse proxy (Caddy/Nginx) routes by subdomain:
- `app.rentease.com` → `customer-web:3000` → `api-public:8000`
- `admin.rentease.com` → `admin-web:3000` → `api-admin:8000`
- (no public `api.rentease.com` — each frontend only ever reaches its own backend instance, kept on the internal Docker network)

This is still "one VM, docker-compose" per your MVP tech stack decision — you're adding one extra service definition (`api-admin`), not new infrastructure. If `api-public` crashes under a traffic spike or a bad deploy, Docker restarts *that* container only; `api-admin` keeps running and staff can keep confirming bookings and recording payments uninterrupted. When you outgrow one VM, `api-public`/`customer-web` scale out independently of `api-admin`/`admin-web` — customer traffic will always dwarf admin traffic, so this is also where the split starts paying for itself on cost, not just resilience.

---

## 9. What this buys you for interviews

This split is a legitimate talking point beyond RentEase's CRUD surface: you can speak to *why* you isolated auth cookies by subdomain, *why* the API runs as two instances of one codebase instead of two separate services, and the tradeoff between a full microservices split (overkill here — see Section 0) vs. this modular-monolith-with-two-instances approach (right-sized for the MVP's actual failure-isolation need without taking on distributed-systems cost).