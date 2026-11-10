# CrowdSec Threat-Intel Hub

One click deploys a central CrowdSec brain: the Local API (LAPI) with its
community blocklist feed (CAPI), backed by Postgres, plus a Metabase
dashboard — all state on persistent volumes, all variables pre-wired, zero
prompts at deploy time.

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/crowdsec-threat-hub)

## What you get

- **crowdsec** — CrowdSec engine v1.8.2 (digest-pinned official image) with a
  small Railway boot wrapper. Runs the Local API on port 8080, registers with
  the online Central API (CAPI) on first boot, and pulls community blocklists.
  A preset bouncer named EDGE is auto-registered at boot; its API key is in
  the crowdsec service Variables tab as BOUNCER_KEY_EDGE.
- **postgres** — Postgres 18 (digest-pinned) holds CrowdSec data (alerts,
  decisions, bouncers) and the Metabase application database.
- **dashboard** — current Metabase OSS (digest-pinned) wired to Postgres via
  MB_DB_CONNECTION_URI. Browse alerts, decisions and blocked IPs with
  Metabase's question builder.

Volumes persist /var/lib/crowdsec (config, credentials, hub, data files) and
/var/lib/postgresql, so decisions, bouncer keys and CAPI credentials survive
redeploys. Healthcheck: /health on crowdsec (unauthenticated, DB-gated); the
dashboard uses the pinned target port instead (Metabase's dotless routes are
all auth-gated, and Railway rejects dots in healthcheck paths).
Restart policy: ON_FAILURE with 10 retries.

## Honest positioning

A Railway container has no host logs to parse, so this is not an IPS running
on the Railway box. It is the central CrowdSec instance: decisions are made
and stored here, community blocklists flow in here, and remediation
components (bouncers) that you run on your own edge services — nginx, Caddy,
Traefik, anything with an HTTP bouncer — poll this hub and enforce. Bouncers
can live inside the same Railway project (use crowdsec.railway.internal:8080)
or anywhere on the internet (use the crowdsec public domain with the API
key). This hub role is exactly what the two existing CrowdSec-related
Railway listings do not provide: crowdsec-or-just-updated-intrusion-preve is
a LAPI-only image with zero deploys, and bunkerweb-aio-with-crowdsec bundles
CrowdSec inside BunkerWeb with one deploy and zero percent health. Pair this
template with the Wazuh template on the marketplace to turn XDR alerts into
active blocking decisions.

## Bouncer quickstart

1. Open the crowdsec service Variables tab and copy BOUNCER_KEY_EDGE.
2. Point your bouncer at the crowdsec service public domain (shown under
   Settings - Networking) and authenticate with that key as the X-API-Key
   header. Example probe from your machine:
   curl -H "X-API-Key: YOUR-EDGE-KEY" https://your-crowdsec-domain.up.railway.app/v1/decisions
3. Add more bouncers any time:
   railway ssh -s crowdsec -- cscli bouncers add my-nginx-bouncer -o raw
4. Test enforcement with a throwaway decision:
   railway ssh -s crowdsec -- cscli decisions add --ip 203.0.113.9 --duration 4h
   then watch your bouncer block that IP. Remove it with
   cscli decisions remove --ip 203.0.113.9.

## Disclosures

- The dashboard is current Metabase OSS, not the preconfigured
  crowdsecurity/metabase image upstream ships for the classic dashboard
  (that image lags versions). You get stock Metabase against Postgres; build
  your own questions, or import dashboards later.
- Console enrollment (app.crowdsec.net) is optional and not configured by
  default: run cscli console enroll with a key from your CrowdSec console if
  you want centralized signal sharing beyond CAPI blocklists.
- The LAPI port is exposed on a public domain so out-of-project bouncers can
  reach it. Decisions and bouncer endpoints require an API key; agent
  registration stays limited to trusted IPs (localhost by default, as
  upstream ships). For hardening: prefer the private network for in-project
  bouncers, rotate BOUNCER_KEY_EDGE from the Variables tab if needed.

# Deploy and Host

Deploying takes one click and provisions the three services (crowdsec,
postgres, dashboard), the two persistent volumes, both public domains and
every variable. Nothing to type: secrets are generated per deploy
(POSTGRES_PASSWORD, BOUNCER_KEY_EDGE) and cross-service references wire the
database in automatically. First boot takes about a minute: the crowdsec
service waits for Postgres, rewrites its db_config to pgx, syncs the hub,
registers the EDGE bouncer and starts the Local API; the dashboard runs
Metabase migrations on first start.

## About Hosting

Hosting a central CrowdSec hub means you own your threat-intelligence store:
decisions, alerts and bouncer registrations live in your Postgres, not in a
vendor SaaS. The engine subscribes to the free community blocklist (CAPI) so
known-bad IPs are blocked proactively, and your own signals can be added with
cscli decisions add or via the console. The Local API is a small Go service;
RAM footprint measured on the reference deployment is roughly 120 to 160 MB
for crowdsec (with community blocklists loaded), about 70 to 100 MB for
Postgres, and 1.0 to 1.3 GB for Metabase, whose JVM heap is capped at 700 MB
via JAVA_OPTS to keep the dashboard service predictable. The
LAPI healthcheck endpoint is /health (unauthenticated and DB-gated, with a
300 second window for the first-boot hub sync and migrations); the dashboard
is gated on the container being up plus its own restart policy instead,
because Metabase has no dotless unauthenticated route and Railway rejects
dots in healthcheck paths.

## Why Deploy

Because bouncer infrastructure is stateful and boring to babysit: registration
records, machine credentials, hub caches and decisions must survive restarts
and redeploys. This template wires the volume-at-parent-path layout CrowdSec
expects (config and data both inside /var/lib/crowdsec), a TCP-gated boot
wrapper that exits non-zero when Postgres is unreachable (so Railway's
ON_FAILURE policy does its job), yq-driven db_config switching to pgx, and an
auto-registered bouncer key — the parts that usually make self-hosting
CrowdSec fiddly are done. You also get a working Metabase instance against
Postgres without touching the Metabase setup wizard wiring yourself.

## Common Use Cases

- Central blocklist hub: run the official nginx or Caddy bouncers on your
  edge sites (hosted anywhere) and have them poll this hub.
- Shared threat intel for a fleet: multiple Railway projects' bouncers pull
  decisions from one hub on the private network.
- Reputation feed caching: CAPI community blocklists materialize into
  decisions here and are served to all bouncers.
- Alert triage: explore alerts, decisions and bouncer activity in Metabase.
- Enrichment sink for SIEM pipelines: push decisions from Wazuh or other
  detectors via the Local API, then enforce them with bouncers.

## Dependencies for

The template is self-contained: crowdsec, postgres and dashboard are all
deployed by this template with their Dockerfiles from the linked GitHub
repository (github.com/lNamelessl/crowdsec-railway-template). Optional
externals: a CrowdSec console enrollment key from app.crowdsec.net if you
want console integration, and an HTTP bouncer on your edge service (nginx,
Caddy, Traefik or any of the official remediation components) to actually
enforce decisions.

### Deployment Dependencies

- Postgres 18-alpine (digest-pinned) — provisioned by the template as the
  postgres service; CrowdSec uses the pgx driver (sslmode disabled over
  Railway's private network) and Metabase uses it as its application store.
- CrowdSec v1.8.2 official image (digest-pinned) — the crowdsec service; a
  boot wrapper prepares the volume layout, waits for Postgres, and switches
  db_config before handing off to the upstream entrypoint, which handles hub
  sync, CAPI registration and BOUNCER_KEY_EDGE registration.
- Metabase OSS (digest-pinned, v0.65.x) — the dashboard service, configured
  with MB_JETTY_PORT=8080, a 700 MB JVM heap cap and
  MB_DB_CONNECTION_URI composed from Postgres service references.
- Persistent volumes at /var/lib/crowdsec (crowdsec) and /var/lib/postgresql
  (postgres). No external database, no external queue, no paid services.
