#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${API_BASE_URL:-}" ]]; then
  echo "Define API_BASE_URL en las variables de entorno de Vercel."
  exit 1
fi

flutter_version="${FLUTTER_VERSION:-3.47.3}"
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
"$flutter_bin" build web --release --dart-define="API_BASE_URL=${API_BASE_URL%/}"
