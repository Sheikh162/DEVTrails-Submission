# Vritti Core Backend

Node.js/TypeScript API for Vritti's parametric income-protection platform. This service owns rider onboarding, wallet and policy records, telemetry ingestion, disruption evaluation, premium renewal, payout history, and integration with the Python ML pricing engine.

## Responsibilities

- Authenticate riders with OTP-style login and create their initial wallet/policy records.
- Store rider profiles, policies, heartbeats, disruption checks, events, payouts, and notifications in PostgreSQL through Prisma.
- Accept edge telemetry from the Flutter app and persist the fraud status used during one-touch claim evaluation.
- Evaluate city disruptions by combining weather/news/activity signals and trigger eligible payouts.
- Call the pricing engine for personalized weekly premium quotes and batch renewal pricing.
- Run scheduled jobs for external data ingestion, R-alert refresh, daily disruption checks, and Saturday policy renewals.

## Tech Stack

- Runtime: Node.js with TypeScript ES modules
- API: Express 5
- Database: PostgreSQL
- ORM: Prisma 7
- Scheduling: node-cron
- External calls: Axios

## Setup

Install dependencies:

```bash
npm install
```

Create `backend/.env` or a root `.env` file with at least:

```env
DATABASE_URL=postgresql://USER:PASSWORD@HOST:PORT/DATABASE
PORT=3000
PRICING_ENGINE_URL=http://localhost:8000
NODE_ENV=development
```

Generate Prisma client and sync the schema as needed:

```bash
npx prisma generate
npx prisma db push
```

Seed demo data:

```bash
npx prisma db seed
```

Run locally:

```bash
npm run dev
```

Build and run production output:

```bash
npm run build
npm start
```

## Main Endpoints

- `GET /health` returns backend health.
- `POST /api/v1/auth/request-otp` starts login/signup.
- `POST /api/v1/auth/verify-otp` verifies OTP and provisions user state.
- `GET /api/v1/auth/profile/:userId` returns rider profile data.
- `POST /api/v1/user/location` syncs rider location.
- `POST /api/v1/telemetry/heartbeat` stores edge fraud telemetry.
- `GET /api/v1/user/heartbeat/:userId` returns latest heartbeat status.
- `GET /api/v1/user/dashboard/:userId` powers the mobile dashboard.
- `POST /api/v1/intelligence/evaluate` evaluates disruption status for a city.
- `GET /api/v1/intelligence/history/:city` returns past disruption checks.
- `GET /api/v1/intelligence/status/:city` returns current city disruption state.
- `POST /api/v1/claims/one-touch` evaluates and triggers a parametric claim.
- `POST /api/v1/premium/renew` runs weekly premium renewal.
- `GET /api/v1/premium/policies/:userId` returns policy history.
- `GET /api/v1/premium/estimate?city=&userId=` returns a premium estimate.
- `GET /api/v1/pricing/health` checks the ML pricing engine.
- `GET /api/v1/pricing/r-alert/:city` proxies R-alert multiplier lookup.
- `GET /api/v1/pricing/quote/:userId` returns a personalized ML premium quote.
- `POST /api/v1/pricing/predict` passes raw prediction payloads to the ML engine.
- `GET /api/v1/payouts/:userId` returns payout history.

Demo endpoints live under `/api/demo/*` for hackathon flows such as forced disruption checks, forced renewals, seeded heartbeat state, and pricing quote breakdowns.

## Scheduled Jobs

- Every 4 hours: ingest external weather and news data for Chennai.
- Every 6 hours: refresh R-alert multiplier from the pricing engine.
- Daily at 14:00: run afternoon disruption evaluation.
- Daily at 20:00: run evening disruption evaluation.
- Saturday at 23:55: process weekly premium renewals with ML batch pricing.

## Project Structure

```text
backend/
|-- prisma/
|   `-- schema.prisma
|-- src/
|   |-- config/
|   |-- modules/
|   |-- main.ts
|   |-- routes.ts
|   `-- seed.ts
|-- package.json
|-- prisma.config.ts
`-- tsconfig.json
```

See [src/README.md](./src/README.md) for module responsibilities and [prisma/README.md](./prisma/README.md) for the database model map.
