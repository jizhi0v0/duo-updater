-- Today's occupied buckets: 16 bits of HMAC(key, day + network), where the
-- network is the IPv4 address or an IPv6 address's /64 prefix.
-- Deleted every night once the day is rolled up.
CREATE TABLE buckets (
  day     TEXT NOT NULL,
  version TEXT NOT NULL,
  bucket  INTEGER NOT NULL,
  PRIMARY KEY (day, version, bucket)
);

-- What is kept: estimated installs per day and app version.
CREATE TABLE daily (
  day      TEXT NOT NULL,
  version  TEXT NOT NULL,
  installs INTEGER NOT NULL,
  PRIMARY KEY (day, version)
);
