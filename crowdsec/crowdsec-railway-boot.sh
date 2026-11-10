#!/bin/bash
# CrowdSec Railway boot wrapper.
#
# Runs before the upstream /docker_start.sh to:
#   (a) back /etc/crowdsec by the Railway volume mounted at /var/lib/crowdsec
#       (the mount parent of /var/lib/crowdsec/data), and
#   (b) point db_config at the Railway Postgres service when DB_HOST is set.
# It then hands off to the upstream entrypoint, keeping every upstream
# behavior intact: hub preloads, online-API (CAPI) registration,
# BOUNCER_KEY_* bouncer registration, and LAPI startup.
set -e

ETC=/etc/crowdsec
ETC_VOL=/var/lib/crowdsec/etc-crowdsec

# (a) Persist /etc/crowdsec into the volume: replace the (absent or
# ephemeral) image directory with a symlink into /var/lib/crowdsec.
# The upstream entrypoint's `rsync --ignore-existing` from /staging then
# populates INTO the volume, so config, credentials and the hub survive
# restarts and redeploys.
mkdir -p "$ETC_VOL"
if [ ! -L "$ETC" ]; then
    if [ -d "$ETC" ]; then
        cp -a "$ETC"/. "$ETC_VOL"/
        rm -rf "$ETC"
    fi
    ln -s "$ETC_VOL" "$ETC"
fi
echo "crowdsec-railway-boot: /etc/crowdsec backed by $ETC_VOL"

# Populate the volume config from the image staging dir. Same semantics as
# the upstream entrypoint: --ignore-existing never overwrites files that are
# already persisted in the volume.
if [ -d /staging/etc/crowdsec ]; then
    rsync -a --ignore-existing /staging/etc/crowdsec/ "$ETC"/
fi

# (b) If DB_HOST is set, wait for Postgres, then rewrite db_config on the
# volume-backed config.yaml. Exit non-zero when Postgres is unreachable so
# the ON_FAILURE restart policy fires instead of looping silently.
if [ -n "$DB_HOST" ]; then
    echo "crowdsec-railway-boot: DB_HOST set, waiting for Postgres at ${DB_HOST}:5432 (max 60s)"
    ok=0
    for i in $(seq 1 60); do
        if (echo > /dev/tcp/"$DB_HOST"/5432) 2>/dev/null; then
            ok=1
            echo "crowdsec-railway-boot: Postgres reachable after ${i}s"
            break
        fi
        sleep 1
    done
    if [ "$ok" != "1" ]; then
        echo "FATAL: Postgres ${DB_HOST}:5432 not reachable within 60s, exiting so Railway restarts us" >&2
        exit 1
    fi
    yq -i '.db_config.type = "pgx"' "$ETC/config.yaml"
    yq -i '.db_config.host = strenv(DB_HOST)' "$ETC/config.yaml"
    yq -i '.db_config.port = 5432' "$ETC/config.yaml"
    yq -i '.db_config.user = strenv(DB_USER)' "$ETC/config.yaml"
    yq -i '.db_config.password = strenv(DB_PASSWORD)' "$ETC/config.yaml"
    yq -i '.db_config.db_name = strenv(DB_NAME)' "$ETC/config.yaml"
    yq -i '.db_config.sslmode = "disable"' "$ETC/config.yaml"
    echo "crowdsec-railway-boot: db_config set to pgx ${DB_HOST}:5432/${DB_NAME}"
fi

# (c) Hand off to the upstream entrypoint.
exec /bin/bash /docker_start.sh
