#!/usr/bin/env bash
set -euo pipefail

flutter_version="${FLUTTER_VERSION:-3.47.3}"
# Flutter reads compile-time definitions, not the build process environment.
# Only this public URL is embedded; bridge tokens must remain in Railway.
api_url="${API_URL:-${API_BASE_URL:-https://bknd.gudex.cl}}"
api_url="${api_url%/}"
build_tmp="$(mktemp -d)"
trap 'rm -rf "$build_tmp"' EXIT
archive_url="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${flutter_version}-stable.tar.xz"

echo "Descargando Flutter ${flutter_version} para compilar Flutter Web..."
curl --fail --location --silent --show-error "$archive_url" | tar -xJ -C "$build_tmp"
flutter_bin="$build_tmp/flutter/bin/flutter"

# Vercel may run builds as root while the extracted SDK files have another
# owner. Trust only this temporary Flutter checkout so Git accepts its repo.
export GIT_CONFIG_GLOBAL="$build_tmp/gitconfig"
git config --global --add safe.directory "$build_tmp/flutter"

"$flutter_bin" config --no-analytics
"$flutter_bin" precache --web
"$flutter_bin" pub get
"$flutter_bin" build web --release --dart-define="API_URL=$api_url"

# Each successful deployment exposes an immutable identifier. The installed
# PWA polls this small, uncached file and offers the user a controlled reload
# whenever Vercel publishes a newer build.
deploy_version="${VERCEL_DEPLOYMENT_ID:-${VERCEL_GIT_COMMIT_SHA:-${GITHUB_SHA:-}}}"
if [[ -z "$deploy_version" ]]; then
  deploy_version="$(git rev-parse --verify HEAD 2>/dev/null || date -u +%Y%m%d%H%M%S)"
fi
printf '{"version":"%s"}\n' "$deploy_version" > build/web/app-version.json
sed -i "s/__GUDEX_DEPLOY_VERSION__/$deploy_version/g" build/web/index.html
