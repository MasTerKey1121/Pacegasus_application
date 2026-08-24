# Pacegasus API

Pacegasus is a REST API for a running companion application. It supports account access, runner onboarding, training-program quests, run-session tracking, daily wellness, RPE (Rate of Perceived Exertion), side quests, and game progress.

The implementation currently in this repository is the Node.js/Express backend in [`backend/`](backend/). The API uses PostgreSQL (including Supabase PostgreSQL) and JSON responses under the `/api` prefix.

## Features implemented

- Email OTP authentication, refresh-token rotation, logout, and Google ID-token sign-in.
- A four-step runner onboarding flow: basic data, injury/condition history, goals, and running history.
- Daily wellness check-ins with five 1–5 scores and a calculated wellness score.
- Program templates, automatic or manual program schedules, main-quest creation/completion, and date-range queries.
- Running-session lifecycle: start, complete, abandon, detail, and history; GPS route points and heart-rate fields are supported.
- Side-quest selection, progress, completion, photo album retrieval, and game rewards.
- RPE logging, history filters, and a training-load risk index.
- Full profile, game-progress retrieval, soft account deletion, request logging, and protected API routes.

## Technology

- Node.js and Express 4
- PostgreSQL via `pg` (compatible with Supabase PostgreSQL)
- JWT, Google Auth Library, Nodemailer, Joi, Helmet, CORS, and rate limiting

## Quick start

Prerequisites: Node.js, npm, and a PostgreSQL database with the `pgcrypto` extension available (required by the UUID defaults in the schema).

```bash
cd backend
npm install
Copy-Item .env.example .env       # PowerShell
# cp .env.example .env            # macOS/Linux
```

Update the values in `.env`, especially `DATABASE_URL`, both JWT secrets, SMTP credentials, and `GOOGLE_CLIENT_ID` if Google sign-in is used.

Create an empty database, then apply the base schema and each additive migration in order:

```bash
npm run migrate
node src/db/migrate.js src/db/003_create_daily_wellness_checkins.sql
node src/db/migrate.js src/db/004_add_running_session_gps_and_hr.sql
node src/db/migrate.js src/db/005_add_users_policy_acceptance.sql
node src/db/migrate.js src/db/006_add_usage_log.sql
node src/db/migrate.js src/db/007_add_program_template_descriptions.sql
node src/db/migrate.js src/db/008_create_rpe_logs.sql
node src/db/migrate.js src/db/009_add_game_progress.sql
node src/db/migrate.js src/db/010_add_user_program_soft_delete.sql
```

The migration runner accepts an explicit path relative to `backend/`; therefore the `src/db/` prefix is required for additive migrations.

Run the server:

```bash
npm run dev     # development with nodemon
npm start       # production-style start
```

The default server URL is `http://localhost:4000`; verify it with:

```bash
curl http://localhost:4000/api/health
```

## Configuration

| Variable | Purpose |
| --- | --- |
| `PORT`, `NODE_ENV`, `CLIENT_URL` | Server port, environment, and allowed CORS origin |
| `DATABASE_URL`, `DB_SSL` | PostgreSQL connection string and SSL toggle |
| `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET` | Separate secrets for access and refresh tokens |
| `JWT_ACCESS_EXPIRES_IN`, `JWT_REFRESH_EXPIRES_IN` | Token lifetimes (defaults: 15m and 30d) |
| `OTP_*` | OTP length, expiry, attempt limit, and resend cooldown |
| `SMTP_*` | SMTP transport and sender information for email OTP |
| `GOOGLE_CLIENT_ID` | Google OAuth web-client ID for ID-token validation |

Do not commit `.env` or real credentials.

## API overview

All endpoints below are prefixed with `/api`. Except for health and authentication requests, send `Authorization: Bearer <accessToken>`.

| Area | Endpoints |
| --- | --- |
| Health | `GET /health` |
| Auth | `POST /auth/otp/request`, `POST /auth/otp/verify`, `POST /auth/google`, `POST /auth/refresh`, `POST /auth/logout`, `GET /auth/me` |
| Onboarding | `GET /onboarding/status`, `PUT /onboarding/step1` through `PUT /onboarding/step4` |
| Profile | `GET /users/me/full`, `GET /users/me/progress`, `DELETE /users/me` |
| Wellness | `GET /wellness-checkin/today`, `POST /wellness-checkin`, `PUT /wellness-checkin`, `GET /wellness-checkin/history?days=30` |
| Programs | `GET /programs/templates`, `POST /programs/start`, `DELETE /programs/current`, `GET /programs/current/week`, `GET/POST /programs/quests`, `POST /programs/quests/batch`, `PATCH /programs/quests/:questId/complete`, `DELETE /programs/quests/:questId` |
| Running | `POST /running-sessions`, `GET /running-sessions/history`, `GET /running-sessions/:id`, `PATCH /running-sessions/:id/complete`, `PATCH /running-sessions/:id/abandon` |
| RPE | `POST /rpe`, `GET /rpe/history`, `GET /rpe/risk-index` |
| Side quests | `GET /quests/side`, `POST /quests/running-sessions/:id/side-quests`, `PATCH /quests/side-quests/:id/progress`, `PATCH /quests/side-quests/:id/finish`, `GET /quests/side-quests/:id/album` |

For registration OTP requests, provide `purpose: "register"`, `policyAccepted: true`, and a `policyVersion`. OTP endpoints are rate-limited. The canonical Side Quest endpoints are under `/api/quests`; the server currently also exposes compatibility aliases.

Detailed request examples are available in the tracked Postman collection: [`test/Pacegasus_API_postman_collection (1).json`](test/Pacegasus_API_postman_collection%20(1).json).

## Cancel a training program

Use `DELETE /api/programs/current` with the authenticated user's bearer token to cancel that user's active training program. The endpoint has no request body.

It is a soft delete: the `user_programs` row is retained, `status` changes to `cancelled`, and `deleted_at` is set. Related quests, baselines, and progress records are retained for history. A cancelled program is no longer active, so the user may start another program. If the user has no active program, the endpoint returns `404`.

Example successful response:

```json
{
  "success": true,
  "message": "ยกเลิกโปรแกรมสำเร็จ",
  "data": {
    "userProgramId": "uuid",
    "programTemplateId": "uuid",
    "startDate": "2026-08-23",
    "scheduleMode": "auto",
    "status": "cancelled",
    "deletedAt": "2026-08-23T10:30:00.000Z"
  }
}
```

Import the main [Postman collection](test/Pacegasus_API_postman_collection%20(1).json), set `accessToken`, create a program first with `POST /api/programs/start`, then run **5.6 Cancel Current Program (Soft Delete)**.

## Tests

The project uses Node's built-in test runner. From `backend/`:

```bash
node --test tests/*.test.js
```

The current tests cover program-template and batch-quest behavior, running-session service/controller behavior, and side-quest handler availability. They use mocked database calls; integration testing still requires a configured database and environment.

## Repository layout

```text
backend/
  src/
    config/       environment and database connection
    controllers/  HTTP handlers
    db/           base schema and additive migrations
    middleware/   auth, error handling, usage logging
    routes/       endpoint registration
    services/     domain and database operations
    utils/        validation and error helpers
  tests/          Node test files
  .env.example   environment template
postman/          Postman workspace metadata
test/             Postman API collection
```

## Notes for deployment

- Set `CLIENT_URL` to the exact browser frontend origin when cookies/credentials are used.
- Set `DB_SSL=true` for database providers that require TLS (such as many hosted PostgreSQL/Supabase deployments).
- Ensure Node.js satisfies all dependencies. The currently included `@supabase/supabase-js` dependency requires Node.js 22 or later through its transitive packages.
