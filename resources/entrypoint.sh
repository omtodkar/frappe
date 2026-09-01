#!/bin/bash
# The sites directory is a volume at runtime, which shadows the assets built
# into the image. Link the image-layer copy back in on every start so a pod
# always serves the assets belonging to its own image.
set -eu

ASSETS_PATH="/home/frappe/frappe-bench/sites/assets"
BAKED_PATH="/home/frappe/frappe-bench/assets"

if [ -d "$BAKED_PATH" ]; then
	rm -rf "$ASSETS_PATH"
	mkdir -p "$(dirname "$ASSETS_PATH")"
	ln -s "$BAKED_PATH" "$ASSETS_PATH"
fi

exec "$@"
