#!/usr/bin/env bash
# Copy the art git does not carry to the R2 bucket game-of-crowns-assets.
# Copy only: never syncs or deletes on R2; skips files already there at the same size.
#
#   realm/assets/          -> realm-assets/   (the whole folder, gitignored third-party art included)
#   bake-off outputs       -> bakeoff/        (concepts, cutouts, ai3d .glb, renders; logs skipped)
#
# Keys come from an env file (R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY); nothing is printed.
#   GOC_R2_ENV      env file          (default: ~/wednesday/off-grid-ai/mobile/.env.keygen)
#   GOC_R2_ACCOUNT  Cloudflare account (default: the account that owns the bucket)
#   GOC_R2_BUCKET   bucket            (default: game-of-crowns-assets)
#   GOC_BAKEOFF     bake-off folder   (default: the side-session notes path below; skipped if missing)
#   Extra args go to rclone, e.g. --dry-run.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENV_FILE="${GOC_R2_ENV:-$HOME/wednesday/off-grid-ai/mobile/.env.keygen}"
ACCOUNT="${GOC_R2_ACCOUNT:-0693da34a224264a4ec10f07fc8336ae}"
BUCKET="${GOC_R2_BUCKET:-game-of-crowns-assets}"
BAKEOFF="${GOC_BAKEOFF:-$HOME/Library/Application Support/Claude/side-session-notes/local_db7df5e6-a688-4652-832c-91640b1273c5/bakeoff}"
RCLONE="$(command -v rclone || echo /opt/homebrew/bin/rclone)"

[ -f "$ENV_FILE" ] || { echo "r2_sync: no env file at $ENV_FILE" >&2; exit 1; }
_v() { grep -E "^$1=" "$ENV_FILE" | head -1 | cut -d= -f2- | sed -E "s/^[\"']//; s/[\"'][[:space:]]*\$//; s/[[:space:]]+\$//"; }

export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
export RCLONE_CONFIG_R2_ACCESS_KEY_ID="$(_v R2_ACCESS_KEY_ID)"
export RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$(_v R2_SECRET_ACCESS_KEY)"
export RCLONE_CONFIG_R2_ENDPOINT="https://${ACCOUNT}.r2.cloudflarestorage.com"

COMMON=(--size-only --transfers 16 --exclude '.DS_Store' --exclude '__pycache__/**' --exclude '*.log' --stats-one-line --stats 30s)

echo "r2_sync: realm/assets -> $BUCKET/realm-assets"
"$RCLONE" copy "$ROOT/realm/assets" "r2:$BUCKET/realm-assets" "${COMMON[@]}" "$@"

if [ -d "$BAKEOFF" ]; then
  echo "r2_sync: bake-off -> $BUCKET/bakeoff"
  "$RCLONE" copy "$BAKEOFF" "r2:$BUCKET/bakeoff" "${COMMON[@]}" "$@"
else
  echo "r2_sync: no bake-off folder at $BAKEOFF, skipped"
fi
