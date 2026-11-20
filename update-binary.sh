#!/usr/bin/env bash
# Docker counterpart of update-binaries.ps1: fetch the Project Reclaimer dedicated server from
# the project's GitHub release at container start, verify its SHA-256 and cache it in the
# /cache volume. The image itself never contains the binary.
#   RECLAIMER_VERSION   latest (default) or a tag such as v0.10.7
#   UPDATE_ON_START     true (default); false keeps the cached version and skips the network
set -euo pipefail

DEST="${RECLAIMER_BIN_DIR:-/cache/bin}"
VERSION="${RECLAIMER_VERSION:-latest}"
log() { echo "[update] $*"; }

case "$(uname -m)" in
  x86_64)  arch=x86_64 ;;
  aarch64) arch=aarch64 ;;
  *) echo "[update] unsupported architecture $(uname -m)" >&2; exit 1 ;;
esac
mkdir -p "$DEST"

if [ "${UPDATE_ON_START:-true}" = false ] && [ -x "$DEST/current/project-reclaimer" ]; then
  log "UPDATE_ON_START=false; using cached $(cat "$DEST/current/VERSION")"
  exit 0
fi

api=https://api.github.com/repos/ProjectReclaimer/project-reclaimer-releases/releases
if [ "$VERSION" = latest ]; then url="$api/latest"; else url="$api/tags/$VERSION"; fi

fallback() {  # network or release problem: keep going on the cached copy if there is one
  if [ -x "$DEST/current/project-reclaimer" ]; then
    log "$1; using cached $(cat "$DEST/current/VERSION")"; exit 0
  fi
  echo "[update] error: $1 and no cached server to fall back on" >&2; exit 1
}

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' "$url" -o "$tmp/release.json" ||
  fallback "could not fetch release info ($VERSION)"

tag="$(jq -r .tag_name "$tmp/release.json")"
name="project-reclaimer-dedicated-${tag}-linux-${arch}.tar.gz"
asset="$(jq -c --arg n "$name" '.assets[] | select(.name == $n)' "$tmp/release.json")"
[ -n "$asset" ] || fallback "release $tag has no asset $name"
expected="$(jq -r '.digest | sub("^sha256:"; "")' <<<"$asset")"
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fallback "no SHA-256 published for $name"

if [ -x "$DEST/$tag/project-reclaimer" ]; then
  log "up to date: $tag"
else
  log "downloading $tag"
  curl -fsSL --retry 3 "$(jq -r .browser_download_url <<<"$asset")" -o "$tmp/$name" ||
    fallback "download of $name failed"
  echo "$expected  $tmp/$name" | sha256sum -c - >/dev/null ||
    fallback "SHA-256 mismatch for $name"
  mkdir -p "$tmp/x"
  tar -xzf "$tmp/$name" -C "$tmp/x" --strip-components=1
  echo "$tag" >"$tmp/x/VERSION"
  rm -rf "$DEST/$tag"
  mv "$tmp/x" "$DEST/$tag"
  log "installed $tag"
fi

ln -sfn "$DEST/$tag" "$DEST/current"
# Keep only the version in use.
find "$DEST" -mindepth 1 -maxdepth 1 -type d ! -name "$tag" -exec rm -rf {} +
