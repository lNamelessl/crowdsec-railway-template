# CrowdSec Threat-Intel Hub on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/crowdsec-threat-hub)

A central **CrowdSec brain** on Railway: the Local API (LAPI), the community
blocklist feed (CAPI), and a Metabase dashboard — deployed as three services
with persistent volumes and **zero required variables**.

**Honest positioning:** a Railway container has no host logs to parse. This
template is not an IPS on the Railway box itself — it is the *central*
CrowdSec instance. It holds decisions, pulls the community blocklist, and
serves them to **bouncers that you run on your own edge services** (anywhere:
Railway, VPS, k8s). Bouncers poll this hub over HTTP with an API key.

## What deploys

| Service | Image | Volume | Notes |
|---|---|---|---|
| `crowdsec` | `crowdsecurity/crowdsec` v1.8.2 (digest-pinned) + small boot wrapper | `/var/lib/crowdsec` | LAPI on port 8080, CAPI blocklists, preset `EDGE` bouncer |
| `postgres` | `postgres:18-alpine` (digest-pinned) | `/var/lib/postgresql` | CrowdSec + Metabase application database |
| `dashboard` | `metabase/metabase` OSS (digest-pinned) | — | Metabase 0.65.x wired to Postgres, MB_DB_CONNECTION_URI |

Public domains are provisioned for `crowdsec` (LAPI + `/health`) and
`dashboard` (Metabase UI). LAPI is reachable publicly because bouncers
usually run outside this project; every decisions/bouncers endpoint requires
an API key. Agent registration (`/api/register`) stays restricted to
`trusted_ips` (localhost only, as upstream ships).

## Variables (all auto-wired, nothing to type)

Every variable ships a defaultValue expression — deploys are zero-prompt:

| Service | Variable | Value |
|---|---|---|
| `crowdsec` | `BOUNCER_KEY_EDGE` | `${{ secret(48, "0123456789abcdefABCDEF") }}` — preset bouncer key, auto-registered at boot |
| `crowdsec` | `DB_HOST` / `DB_USER` / `DB_PASSWORD` / `DB_NAME` | references into the `postgres` service |
| `postgres` | `POSTGRES_PASSWORD` | `${{ secret(32, "0123456789abcdefABCDEF") }}` |
| `dashboard` | `MB_DB_CONNECTION_URI` | composed from `postgres` service references |

Secrets are generated once per template deploy and persist for the life of
the project.

## Boot wrapper

`crowdsec/crowdsec-railway-boot.sh` runs before the upstream entrypoint and:

1. Replaces `/etc/crowdsec` with a symlink into `/var/lib/crowdsec/etc-crowdsec`
   (the volume). The upstream entrypoint's `rsync --ignore-existing` from
   `/staging` then populates *into the volume*, so config, machine/bouncer
   credentials and the hub index persist across redeploys.
2. If `DB_HOST` is set: TCP-waits for Postgres up to 60 s (exit 1 on timeout
   so the ON_FAILURE restart policy fires), then rewrites `db_config` to
   `pgx` + your Postgres with `yq` (sslmode disabled; Railway's private
   network is not TLS-terminated).
3. `exec`s the upstream `/docker_start.sh` unchanged.

## Bouncer quickstart

The preset `EDGE` bouncer is registered at first boot; its key is in the
`crowdsec` service Variables tab (`BOUNCER_KEY_EDGE`). Point any HTTP bouncer
at your `crowdsec` public domain with that key:

```
GET https://<your-crowdsec-domain>.up.railway.app/v1/decisions
X-API-Key: <BOUNCER_KEY_EDGE value>
```

Add more bouncers:

```
railway ssh -s crowdsec -- cscli bouncers add my-nginx-bouncer -o raw
```

(the raw output is the API key). Official remediation components:
[crowdsec-nginx-bouncer](https://docs.crowdsec.net/docs/bouncers/nginx),
[caddy-bouncer](https://github.com/hslatkin/caddy-crowdsec-bouncer) and the
[full bouncer list](https://docs.crowdsec.net/docs/bouncers/ref_bouncers/).
In-project bouncers can use `http://crowdsec.railway.internal:8080`.

Test a decision:

```
railway ssh -s crowdsec -- cscli decisions add --ip 203.0.113.9 --duration 4h
railway ssh -s crowdsec -- cscli decisions list
```

## Hardening

- Keep bouncers on the private network (`crowdsec.railway.internal:8080`)
  when they run inside the same Railway project.
- Rotate `BOUNCER_KEY_EDGE` (Variables tab) if a domain or key leaks.
- Optional console enrollment: `railway ssh -s crowdsec -- cscli console
  enroll <enroll-key>` with a key from [app.crowdsec.net](https://app.crowdsec.net).

## Related

- [Wazuh template](https://railway.com/deploy/wazuh-template) — XDR/SIEM;
  pipe Wazuh alerts into CrowdSec decisions for active response.

## Local development

Each service directory is a standalone Dockerfile context; `railway.json`
per service pins builder, healthchecks (`/health` on crowdsec, `/` on
dashboard) and the ON_FAILURE/10 restart policy.
