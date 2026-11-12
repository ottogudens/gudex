#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${API_URL:-}" ]]; then
  echo "API_URL es obligatorio para compilar el frontend de Cloudflare; usa una API de staging." >&2
  exit 2
fi

case "$API_URL" in
  https://*) ;;
  *) echo "API_URL debe usar HTTPS." >&2; exit 2 ;;
esac

export CLOUDFLARE_ACCESS_ENABLED=true
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$script_dir/build_vercel.sh"
