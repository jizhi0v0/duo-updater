// Serves DuoUpdater's Sparkle feed at updates.duoupdater.app/appcast.xml and
// estimates how many installs check for updates each day.
//
// The feed itself still lives in the repo: publish-release.sh commits
// appcast.xml to main, and this Worker relays that file, so releasing needs no
// step here. It only relays: Sparkle verifies every update's EdDSA signature
// against the key baked into the app, so the Worker cannot hand out an update
// the app would accept.
//
// Privacy is the constraint everything here is built around (README "Privacy"
// says the same). Nothing that identifies a person or a Mac is stored:
// - A request only counts when its User-Agent is the one Sparkle sends,
//   "DuoUpdater/<version> Sparkle/<version>"; the app version is the only
//   thing kept from it, and only when the appcast lists that version (any
//   other is counted as "older").
// - The IP is used once, in memory, as input to HMAC(key, day + network), and
//   only 16 bits of that are kept: a bucket number from 0 to 65535. The
//   network is the IPv4 address, or an IPv6 address's /64 prefix. Tens of
//   thousands of IPv4 addresses share every bucket, so a bucket cannot be
//   turned back into an address, even by someone holding the key. The key is
//   a Worker secret, which can be written but never read back.
// - The day is part of the HMAC input, so the same Mac lands in unrelated
//   buckets on different days and cannot be followed over time.
// - Each night the day's buckets are turned into one number per app version
//   (linear counting: installs ≈ -m·ln(1 - buckets/m)) and deleted. Only
//   `daily (day, version, installs)` is kept.
// - No country, no logs: Workers observability is off, and nothing is
//   console.logged per request.
//
// Abuse: the counter is shaped so one machine cannot inflate it. The
// User-Agent is not hashed, so one address fills at most one bucket per
// version; an IPv6 /64, which one person can hold all of, counts as one
// address; and versions the appcast does not list collapse into "older", so
// invented version strings cannot multiply rows. Request flooding is left to
// the zone's rate-limiting rule, which stops it before the Worker runs.

export interface Env {
  DB: D1Database;
  HASH_KEY: string;
}

const UPSTREAM =
  "https://raw.githubusercontent.com/jizhi0v0/duo-updater/main/appcast.xml";

const SPARKLE_UA = /^DuoUpdater\/(\d{1,4}(?:\.\d{1,4}){1,3}) Sparkle\//;

const BUCKETS = 65536;

export default {
  async fetch(request, env, ctx): Promise<Response> {
    const url = new URL(request.url);
    if (url.pathname !== "/appcast.xml") {
      return new Response("Not found\n", { status: 404 });
    }
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method not allowed\n", {
        status: 405,
        headers: { allow: "GET, HEAD" },
      });
    }

    const upstream = await fetch(UPSTREAM, {
      cf: { cacheTtl: 60, cacheEverything: true },
    });
    if (!upstream.ok) {
      return new Response("Feed unavailable\n", { status: 502 });
    }

    const feed = await upstream.text();

    if (request.method === "GET") {
      const match = SPARKLE_UA.exec(request.headers.get("user-agent") ?? "");
      const ip = request.headers.get("cf-connecting-ip");
      if (match && ip) {
        const version = feed.includes(
          `<sparkle:shortVersionString>${match[1]}</sparkle:shortVersionString>`,
        )
          ? match[1]
          : "older";
        // Counting must never delay or fail the update check.
        ctx.waitUntil(record(env, network(ip), version).catch(() => {}));
      }
    }

    return new Response(request.method === "HEAD" ? null : feed, {
      headers: {
        "content-type": "application/xml; charset=utf-8",
        "cache-control": "no-cache",
      },
    });
  },

  async scheduled(_controller, env): Promise<void> {
    await rollUp(env.DB, utcDay(new Date()));
  },
} satisfies ExportedHandler<Env>;

async function record(
  env: Env,
  network: string,
  version: string,
): Promise<void> {
  const day = utcDay(new Date());
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(env.HASH_KEY),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = new Uint8Array(
    await crypto.subtle.sign(
      "HMAC",
      key,
      new TextEncoder().encode(`${day}\n${network}`),
    ),
  );
  const bucket = ((mac[0] << 8) | mac[1]) % BUCKETS;
  await env.DB.prepare(
    "INSERT OR IGNORE INTO buckets (day, version, bucket) VALUES (?1, ?2, ?3)",
  )
    .bind(day, version, bucket)
    .run();
}

// Turns every finished day's buckets into per-version estimates, then deletes
// the buckets.
export async function rollUp(db: D1Database, today: string): Promise<void> {
  const { results } = await db
    .prepare(
      `SELECT day, version, count(*) AS filled FROM buckets
       WHERE day < ?1 GROUP BY day, version`,
    )
    .bind(today)
    .all<{ day: string; version: string; filled: number }>();
  const upserts = results.map((row) =>
    db
      .prepare(
        "INSERT OR REPLACE INTO daily (day, version, installs) VALUES (?1, ?2, ?3)",
      )
      .bind(row.day, row.version, estimate(row.filled)),
  );
  await db.batch([
    ...upserts,
    db.prepare("DELETE FROM buckets WHERE day < ?1").bind(today),
  ]);
}

// Linear counting: corrects for installs that share a bucket.
export function estimate(filled: number): number {
  if (filled >= BUCKETS) return BUCKETS;
  return Math.round(-BUCKETS * Math.log(1 - filled / BUCKETS));
}

// An IPv4 address as is; an IPv6 address cut to its /64 prefix.
export function network(ip: string): string {
  if (!ip.includes(":")) return ip;
  const [head, tail = ""] = ip.split("::");
  const left = head ? head.split(":") : [];
  const right = tail ? tail.split(":") : [];
  const groups = ip.includes("::")
    ? [...left, ...Array(8 - left.length - right.length).fill("0"), ...right]
    : left;
  return groups
    .slice(0, 4)
    .map((g) => parseInt(g || "0", 16).toString(16))
    .join(":");
}

function utcDay(date: Date): string {
  return date.toISOString().slice(0, 10);
}
