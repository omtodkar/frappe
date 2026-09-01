#!/bin/bash
# The sites directory is a volume at runtime, which shadows the assets built
# into the image. Link the image-layer copy back in so a pod always serves the
# assets belonging to its own image.
#
# IDEMPOTENT AND ATOMIC, because in Kubernetes several pods of the same lane
# share one ReadWriteOnce sites volume and start concurrently. A plain
# rm -rf + ln -s would have every pod delete a link the others are already
# serving from, so the assets vanish for a moment on every rollout. Here the
# work is skipped entirely when the link is already correct -- the steady
# state -- and when it is not, the replacement goes through a temporary name
# and one rename() so no reader ever observes a missing path.
set -eu

ASSETS_PATH="/home/frappe/frappe-bench/sites/assets"
BAKED_PATH="/home/frappe/frappe-bench/assets"

if [ -d "$BAKED_PATH" ] && [ "$(readlink "$ASSETS_PATH" 2>/dev/null || true)" != "$BAKED_PATH" ]; then
	mkdir -p "$(dirname "$ASSETS_PATH")"
	# A real directory left by an older image cannot be rename()d over.
	if [ -d "$ASSETS_PATH" ] && [ ! -L "$ASSETS_PATH" ]; then
		rm -rf "$ASSETS_PATH"
	fi
	tmp="$(dirname "$ASSETS_PATH")/.assets.$$"
	ln -sfn "$BAKED_PATH" "$tmp"
	mv -Tf "$tmp" "$ASSETS_PATH"
fi

exec "$@"
