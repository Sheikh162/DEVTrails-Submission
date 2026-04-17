# Backend Source

This folder contains the Express application code for the Vritti Core Backend.

## Entry Points

- `main.ts` builds the Express app, installs middleware, registers routes, starts cron jobs, and launches the server.
- `routes.ts` defines all HTTP routes and wires requests to controllers/services.
- `seed.ts` creates demo users, wallets, policies, activity logs, weather/news records, events, payouts, and heartbeat data.
- `config/prisma.ts` initializes Prisma with the configured PostgreSQL connection.

## Modules

- `auth/` handles OTP request/verification and rider profile lookup.
- `dashboard/` aggregates rider dashboard data.
- `demo/` supports hackathon/demo actions such as simulated weeks.
- `fraud/` receives mobile edge heartbeat telemetry and exposes heartbeat status.
- `ingestion/` pulls external weather/news inputs used by disruption checks.
- `intelligence/` evaluates city disruptions and one-touch claims.
- `location/` syncs rider location.
- `notification/` stores or dispatches rider notifications.
- `payout/` handles payout creation and payout history queries.
- `premium/` estimates premiums, stores policies, and runs weekly renewals.
- `pricing/` adapts backend user/weather data into the ML pricing engine API contract.

## Runtime Notes

Most modules depend on `prisma`, so `DATABASE_URL` must be available before starting the backend. The pricing module falls back when the external engine is unavailable, but accurate premium quotes require `PRICING_ENGINE_URL`.
