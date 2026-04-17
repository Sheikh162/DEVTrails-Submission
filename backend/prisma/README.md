# Prisma Schema

Database schema for the Vritti Core Backend.

## Main Entities

- `User` stores rider identity, city/platform metadata, consent, current location, and edge security status.
- `Wallet` stores rider balance and currency.
- `Policy` stores weekly premium and coverage records.
- `Claim` stores rider claim attempts linked to a policy.
- `ActivityLog` stores delivery activity and earnings history used for pricing.
- `Heartbeat` stores edge telemetry status from the mobile app.
- `WeatherMetric` stores city weather observations.
- `NewsArticle` and `NewsSignal` store disruption intelligence from news ingestion.
- `DisruptionCheck` stores city-level disruption evaluations.
- `Event` stores confirmed disruption events.
- `Payout` stores credits issued for events.
- `Notification` stores rider-facing messages.

## Common Commands

Generate Prisma client:

```bash
npx prisma generate
```

Push schema to the configured database:

```bash
npx prisma db push
```

Open Prisma Studio:

```bash
npx prisma studio
```

Seed demo data from `src/seed.ts`:

```bash
npx prisma db seed
```

The Prisma datasource URL is read from `DATABASE_URL` through `prisma.config.ts`.
