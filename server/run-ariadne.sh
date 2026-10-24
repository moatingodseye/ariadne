#!/usr/bin/env bash
# Ariadne — bring the stack up from the images shipped beside this script.
#
#   chmod +x run-ariadne.sh && ./run-ariadne.sh
#
# NO Dart, NO build step and NO source are needed on this box. The two app
# images are AOT binaries on debian-slim; Postgres is the stock public image.
#
# Re-running is SAFE and is how you upgrade: the app containers are recreated,
# the database and the source store are left alone.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=0.34.5
ENV_FILE="${ARIADNE_ENV:-./ariadne.env}"

# ── settings ────────────────────────────────────────────────────────────────
# The env file wins where it exists; anything already exported wins over that,
# so a one-off override is `ARIADNE_WEB_PORT=9000 ./run-ariadne.sh`.
if [ -f "$ENV_FILE" ]; then
  set -a; . "$ENV_FILE"; set +a
fi
DB_DATA="${ARIADNE_DB_DATA:-/var/lib/ariadne/db}"
SOURCE_DIR="${ARIADNE_SOURCE:-/var/lib/ariadne/source}"
API_PORT="${ARIADNE_API_PORT:-8192}"
WEB_PORT="${ARIADNE_WEB_PORT:-8193}"
PG_IMAGE="${ARIADNE_PG_IMAGE:-docker.io/pgvector/pgvector:pg16}"
ADAPTER_KEY="${ARIADNE_ADAPTER_KEY:-}"
# The container and network names. Parameterised so a second instance can be
# brought up beside a running one without tearing it down - which is also the
# only way this script could be PROVED end to end without stopping the stack
# it was tested next to. Leave it alone for an ordinary deployment.
NAME="${ARIADNE_NAME:-ariadne}"
# Whether the containers come back on their own.
#
# **Default OFF, because autostart is a decision and not a detail.** This
# script used to hardcode `unless-stopped`, which quietly enrolls a box in
# starting something at boot that nobody asked it to start. Set
# ARIADNE_RESTART=unless-stopped if that is what you want; note it only takes
# effect across a reboot where the user has lingering enabled and podman's
# restart unit is active.
RESTART="${ARIADNE_RESTART:-no}"

need() { command -v "$1" >/dev/null 2>&1 || { echo "FAIL: $1 is not installed" >&2; exit 2; }; }
need podman

# ── ARIADNE_SECRET: generated ONCE, then never again ────────────────────────
#
# Generating a fresh one on every run would silently orphan every stored
# database password, which presents as an authentication failure days later and
# reads as a database problem. So it is written to the env file the first time
# and read from it forever after.
if [ -z "${ARIADNE_SECRET:-}" ]; then
  if [ -f "$ENV_FILE" ] && grep -q '^ARIADNE_SECRET=.\+' "$ENV_FILE"; then
    echo "FAIL: $ENV_FILE has a secret this script could not read" >&2; exit 2
  fi
  ARIADNE_SECRET="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  touch "$ENV_FILE"; chmod 600 "$ENV_FILE"
  if grep -q '^ARIADNE_SECRET=' "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^ARIADNE_SECRET=.*|ARIADNE_SECRET=$ARIADNE_SECRET|" "$ENV_FILE"
  else
    printf 'ARIADNE_SECRET=%s\n' "$ARIADNE_SECRET" >> "$ENV_FILE"
  fi
  echo "==> generated ARIADNE_SECRET and wrote it to $ENV_FILE"
  echo "    BACK THIS FILE UP. Lose it and every stored database password is"
  echo "    undecryptable; there is no recovery, only re-entering them."
fi

echo "==> loading the app images (ariadne $VERSION)"
for img in ariadne-api ariadne-web; do
  f="$img-$VERSION.tar.gz"
  [ -f "$f" ] || { echo "FAIL: $f is not beside this script" >&2; exit 2; }
  podman load -i "$f" >/dev/null
  echo "    $img:$VERSION"
done

echo "==> network"
podman network exists "$NAME-net" || podman network create "$NAME-net" >/dev/null

echo "==> postgres"
if ! podman image exists "$PG_IMAGE"; then
  echo "    pulling $PG_IMAGE (once — see DEPLOYMENT.md for the offline route)"
  podman pull "$PG_IMAGE"
fi
mkdir -p "$DB_DATA" "$SOURCE_DIR"
# **Recreated, never rebuilt from nothing.** The data lives in $DB_DATA on the
# host, so removing the container is not removing the database.
podman rm -f "$NAME-db" >/dev/null 2>&1 || true
podman run -d --name "$NAME-db" --network "$NAME-net" --restart "$RESTART" \
  -e POSTGRES_DB=ariadne -e POSTGRES_USER=ariadne -e POSTGRES_PASSWORD=ariadne \
  -v "$DB_DATA":/var/lib/postgresql/data:U \
  -v "$PWD/init.sql":/docker-entrypoint-initdb.d/init.sql:ro \
  "$PG_IMAGE" >/dev/null
printf '    waiting for postgres '
for _ in $(seq 1 90); do
  podman exec "$NAME-db" pg_isready -U ariadne >/dev/null 2>&1 && { echo ready; break; }
  printf .; sleep 1
done
podman exec "$NAME-db" pg_isready -U ariadne >/dev/null 2>&1 \
  || { echo; echo "FAIL: postgres did not come up — podman logs $NAME-db" >&2; exit 3; }

echo "==> ariadne-api"
podman rm -f "$NAME-api" >/dev/null 2>&1 || true
podman run -d --name "$NAME-api" --network "$NAME-net" --restart "$RESTART" \
  -p "${API_PORT}:8090" \
  `# ariadne-web's nginx has "http://ariadne-api:8090" compiled into its` \
  `# config, so a renamed API container would be unreachable from it. The` \
  `# alias keeps that name resolvable whatever the container is called; on an` \
  `# ordinary deployment it is simply the same word twice.` \
  --network-alias ariadne-api \
  -e DB_HOST="$NAME-db" -e DB_PORT=5432 \
  -e DB_NAME=ariadne -e DB_USER=ariadne -e DB_PASSWORD=ariadne \
  -e SOURCE_ROOT=/srv/ariadne/source \
  -e ARIADNE_SECRET="$ARIADNE_SECRET" \
  -e ARIADNE_ADAPTER_KEY="$ADAPTER_KEY" \
  -v "$SOURCE_DIR":/srv/ariadne/source \
  --log-opt max-size=10mb \
  "ariadne-api:$VERSION" >/dev/null

echo "==> ariadne-web"
podman rm -f "$NAME-web" >/dev/null 2>&1 || true
podman run -d --name "$NAME-web" --network "$NAME-net" --restart "$RESTART" \
  -p "${WEB_PORT}:8080" --log-opt max-size=10mb \
  "ariadne-web:$VERSION" >/dev/null

# ── prove it, rather than announce it ───────────────────────────────────────
#
# A script that prints "up" because `podman run` returned has proved that
# podman accepted the arguments and nothing else. The deploy that shipped a
# server which 500'd on its first real question passed exactly that check.
printf '==> health '
ok=
for _ in $(seq 1 60); do
  if curl -fsS -m 3 "http://127.0.0.1:${WEB_PORT}/api/health" >/dev/null 2>&1; then ok=1; echo ok; break; fi
  printf .; sleep 1
done
[ -n "$ok" ] || { echo; echo "FAIL: /api/health never answered through :${WEB_PORT}" >&2
  echo "      podman logs $NAME-api   |   podman logs $NAME-web" >&2; exit 4; }

echo
podman ps --filter "name=$NAME" --format "  {{.Names}}  {{.Status}}  {{.Ports}}"
echo
echo "Ariadne $VERSION is up."
echo "  Web UI / API for clients:  http://$(hostname -I 2>/dev/null | awk '{print $1}'):${WEB_PORT}/"
echo "  Point a client at it:      set ARIADNE_API_URL to that URL"
echo "  Check from anywhere:       curl <that URL>/api/version"
