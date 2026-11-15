#!/usr/bin/env bash
# Bring the game's art back from the R2 bucket game-of-crowns-assets into this checkout (git carries code, data,
# Godot's .import files and licences; the art lives in R2: realm/tools/r2_sync.sh puts it there).
# Copy only: never deletes here; skips files already here at the same size.
#
#   realm-assets/ -> realm/assets/   (what the game loads; always)
#   docs-art/     -> docs/art/       (concepts and targets; with --docs)
#
# Keys as r2_sync.sh (GOC_R2_ENV, GOC_R2_ACCOUNT, GOC_R2_BUCKET). Extra args go to rclone, e.g. --dry-run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${GOC_R2_ENV:-$HOME/wednesday/off-grid-ai/mobile/.env.keygen}"
ACCOUNT="${GOC_R2_ACCOUNT:-0693da34a224264a4ec10f07fc8336ae}"
BUCKET="${GOC_R2_BUCKET:-game-of-crowns-assets}"
RCLONE="$(command -v rclone || echo /opt/homebrew/bin/rclone)"

[ -f "$ENV_FILE" ] || { echo "r2_pull: no env file at $ENV_FILE" >&2; exit 1; }
_v() { grep -E "^$1=" "$ENV_FILE" | head -1 | cut -d= -f2- | sed -E "s/^[\"']//; s/[\"'][[:space:]]*\$//; s/[[:space:]]+\$//"; }

export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$(_v R2_ACCESS_KEY_ID)"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$(_v R2_SECRET_ACCESS_KEY)"
export RCLONE_CONFIG_R2_ENDPOINT="https://${ACCOUNT}.r2.cloudflarestorage.com"

DOCS=0
ARGS=()
for a in "$@"; do [ "$a" = "--docs" ] && DOCS=1 || ARGS+=("$a"); done
COMMON=(--size-only --transfers 16 --stats-one-line --stats 30s)

echo "r2_pull: $BUCKET/realm-assets -> realm/assets"
"$RCLONE" copy "r2:$BUCKET/realm-assets" "$ROOT/realm/assets" "${COMMON[@]}" "${ARGS[@]+"${ARGS[@]}"}"
if [ "$DOCS" = 1 ]; then
  echo "r2_pull: $BUCKET/docs-art -> docs/art"
  "$RCLONE" copy "r2:$BUCKET/docs-art" "$ROOT/docs/art" "${COMMON[@]}" "${ARGS[@]+"${ARGS[@]}"}"
fi
