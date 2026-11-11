#!/usr/bin/env bash
# Deploys the game server to a Railway service from this checkout: stages the build context (server/stage.sh),
# uploads it (`railway up`, a remote Docker build) and waits for the deployment to be live.
#
#   server/deploy.sh <service> [stage folder]
#
# Run it from a folder linked to the project (`railway link -p <project> -e production`, a scratch folder, never the
# game checkout), or with RAILWAY_TOKEN set: with neither, `railway up` makes a new project named after the folder, so
# the script refuses first. The service must exist (`railway add --service <name>`) with a public domain (`railway
# domain --service <name>`). Deploy the web build and the server from one commit: the hello's version check turns away
# a client of another protocol version (kit docs/studio/railway.md#skew).
set -euo pipefail

service=${1:?usage: server/deploy.sh <service> [stage folder]}
stage=${2:-$(mktemp -d)}
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)

if [ -z "${RAILWAY_TOKEN:-}" ] && ! railway status >/dev/null 2>&1; then
    echo "no Railway project: set RAILWAY_TOKEN or run from a folder linked with railway link" >&2
    exit 2
fi

bash "$here/stage.sh" "$stage"
commit=$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo unknown)
timeout "${RAILWAY_UP_SECONDS:-900}" railway up "$stage" --path-as-root --service "$service" --ci \
    --message "game server $commit"

# `up --ci` returns when the build is done; the server is live once its deployment is SUCCESS (it speaks WebSocket
# only, so there is no HTTP health check to wait for). The list is newest first.
for _ in $(seq 1 60); do
    status=$(railway deployment list --service "$service" --json 2>/dev/null \
        | grep -m1 '"status"' | cut -d'"' -f4) || status=""
    echo "deployment: ${status:-unreadable}"
    case $status in
        SUCCESS) exit 0 ;;
        FAILED | CRASHED | REMOVED) exit 1 ;;
    esac
    sleep "${RAILWAY_POLL_SECONDS:-10}"
done
echo "the deployment was not live after ten minutes" >&2
exit 1
