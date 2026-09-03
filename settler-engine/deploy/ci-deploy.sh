#!/usr/bin/env bash
# Pull the published engine image and run it on 127.0.0.1:8080.
# Expected env: GHCR_TOKEN, GHCR_USER, optional SETTLER_ENGINE_TAG.
set -euo pipefail

readonly COMPOSE_FILE="${COMPOSE_FILE:-/opt/settler-engine/docker-compose.yml}"
readonly IMAGE="ghcr.io/pvelleleth/katan/settler-engine"
readonly TAG="${SETTLER_ENGINE_TAG:-latest}"

if [[ -z "${GHCR_TOKEN:-}" || -z "${GHCR_USER:-}" ]]; then
	printf 'GHCR_USER and GHCR_TOKEN are required to pull %s\n' "$IMAGE" >&2
	exit 1
fi

if [[ ! -f "$COMPOSE_FILE" ]]; then
	printf 'Missing compose file: %s\n' "$COMPOSE_FILE" >&2
	exit 1
fi

if systemctl is-active --quiet settler-engine.service; then
	systemctl stop settler-engine.service
fi
if systemctl is-enabled --quiet settler-engine.service 2>/dev/null; then
	systemctl disable settler-engine.service
fi

cleanup() {
	docker logout ghcr.io >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "$GHCR_TOKEN" | docker login ghcr.io -u "$GHCR_USER" --password-stdin >/dev/null

export SETTLER_ENGINE_TAG="$TAG"
docker compose -f "$COMPOSE_FILE" pull
docker compose -f "$COMPOSE_FILE" up -d --remove-orphans --force-recreate --wait --wait-timeout 60

for attempt in {1..20}; do
	if curl --fail --silent --show-error --max-time 3 http://127.0.0.1:8080/health >/dev/null; then
		printf 'Engine healthy on 127.0.0.1:8080 (%s:%s)\n' "$IMAGE" "$TAG"
		exit 0
	fi
	sleep 1
done

printf 'Container started but /health did not pass. Recent logs:\n' >&2
docker compose -f "$COMPOSE_FILE" logs --tail 80 >&2
exit 1
