#!/usr/bin/env bash
# Build, push, and deploy to Zero. Requires Docker running, docker login to your registry,
# and for private images: zero registry login <server> --user <u> --password <p>
#
# Loads ./.env into zero deploy --env (comma-separated) when LOAD_DOTENV is not 0.
# Values must not contain commas (zero CLI limitation). Skip with LOAD_DOTENV=0.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Build KEY=val,KEY2=val2 from .env (KEY=VALUE lines; # comments; strip CR; optional quotes)
zero_env_from_file() {
	local f="${ROOT}/.env"
	[[ -f "$f" ]] || return 0
	local line k v csv=""
	while IFS= read -r line || [[ -n "$line" ]]; do
		line="${line%%$'\r'}"
		[[ -z "${line//[[:space:]]/}" ]] && continue
		[[ "$line" =~ ^[[:space:]]*# ]] && continue
		[[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
		k="${BASH_REMATCH[1]}"
		v="${BASH_REMATCH[2]}"
		if [[ "$v" =~ ^\".*\"$ ]]; then v="${v#\"}"; v="${v%\"}"; fi
		if [[ "$v" =~ ^\'.*\'$ ]]; then v="${v#\'}"; v="${v%\'}"; fi
		[[ -n "$csv" ]] && csv+=","
		csv+="${k}=${v}"
	done <"$f"
	[[ -n "$csv" ]] && printf '%s' "$csv"
}
TAG="${TAG:-latest}"
# Default: ghcr.io/<github-owner> from origin (override with REGISTRY=docker.io/you)
if [[ -z "${REGISTRY:-}" ]]; then
	_url="$(git -C "${ROOT}" remote get-url origin 2>/dev/null || true)"
	if [[ "${_url}" =~ github\.com[:/]([^/]+)/ ]]; then
		REGISTRY="ghcr.io/${BASH_REMATCH[1]}"
	else
		echo "Set REGISTRY (e.g. ghcr.io/myuser or docker.io/myuser)" >&2
		exit 1
	fi
fi
# Match most Linux VPS (amd64); override with PLATFORM=linux/arm64 if needed
PLATFORM="${PLATFORM:-linux/amd64}"
IMAGE="${REGISTRY}/settler-engine:${TAG}"

docker build --platform "${PLATFORM}" -t "${IMAGE}" "${ROOT}"
docker push "${IMAGE}"

ZERO_ENV_ARGS=()
if [[ "${LOAD_DOTENV:-1}" != "0" ]]; then
	_csv="$(zero_env_from_file)"
	[[ -n "${_csv}" ]] && ZERO_ENV_ARGS+=(--env "${_csv}")
fi
exec zero deploy "${IMAGE}" --port 8080 "${ZERO_ENV_ARGS[@]}" "$@"
