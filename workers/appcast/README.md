# updates.duoupdater.app

The Cloudflare Worker that serves DuoUpdater's Sparkle feed and estimates daily
installs. What it stores, and why that cannot identify anyone, is written at the
top of [`src/index.ts`](src/index.ts) and in the main README's *Privacy* section.

Releasing needs nothing here: `scripts/publish-release.sh` commits
`appcast.xml` to main and the Worker relays that file (cached for 60 s).

## First deploy

```sh
npm install
npx wrangler login
npx wrangler d1 create duoupdater-appcast   # put the id in wrangler.jsonc
npx wrangler d1 migrations apply duoupdater-appcast --remote
openssl rand -hex 32 | npx wrangler secret put HASH_KEY
npx wrangler deploy
```

`HASH_KEY` is never needed again and need not be saved anywhere.

## Reading the numbers

```sh
# Finished days
npx wrangler d1 execute duoupdater-appcast --remote --command \
  "SELECT day, sum(installs) AS installs FROM daily GROUP BY day ORDER BY day DESC LIMIT 30"

# Today so far (occupied buckets per version, before the linear-counting correction)
npx wrangler d1 execute duoupdater-appcast --remote --command \
  "SELECT version, count(*) FROM buckets GROUP BY version"
```

A Mac that updates during the day is counted under both versions, so the
per-day sum can run slightly high on release days.
