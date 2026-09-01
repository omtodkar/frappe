#!/bin/bash
# Reconcile the two things the sites volume shadows, then exec the command.
#
# `sites/` is a mount point at runtime. In Docker a NAMED VOLUME is seeded from
# the image on first use, so upstream's compose setup never notices that
# `sites/apps.txt`, `sites/apps.json` and the built assets live inside the
# image at that path. A Kubernetes PersistentVolumeClaim does NOT do that
# copy: it mounts empty and hides them, and `bench` then dies with
# "./apps.txt Not Found" before it does anything else.
#
# So the image keeps a pristine copy of both outside the mount point and
# restores them here, with two different rules:
#
#   apps.txt / apps.json  ALWAYS refreshed. They describe which apps this
#                         IMAGE contains, so the image is authoritative and a
#                         volume that outlived an older image must not keep a
#                         stale list -- that is exactly how a derived project
#                         image would fail to see its own apps.
#   everything else       SEEDED ONLY IF ABSENT. common_site_config.json and
#                         the site directories are volume state; the image has
#                         no business overwriting them.
#
# Every write goes through a temporary name and one rename(), because several
# pods of the same lane share one ReadWriteOnce volume and start together.
set -eu

BENCH=/home/frappe/frappe-bench
SITES="$BENCH/sites"
SEED="$BENCH/sites-seed"
ASSETS_PATH="$SITES/assets"
BAKED_PATH="$BENCH/assets"

atomic_copy() {
	# $1 source file, $2 destination path
	tmp="$(dirname "$2")/.$(basename "$2").$$"
	cp "$1" "$tmp"
	mv -f "$tmp" "$2"
}

mkdir -p "$SITES"

if [ -d "$SEED" ]; then
	for f in apps.txt apps.json; do
		[ -f "$SEED/$f" ] && atomic_copy "$SEED/$f" "$SITES/$f"
	done
	for f in common_site_config.json; do
		if [ -f "$SEED/$f" ] && [ ! -e "$SITES/$f" ]; then
			atomic_copy "$SEED/$f" "$SITES/$f"
		fi
	done
fi

# The built front-end assets live in an image layer for the same reason, and
# are linked rather than copied. Skipped entirely when already correct -- the
# steady state -- so concurrent pods do not delete a link the others are
# serving from.
if [ -d "$BAKED_PATH" ] && [ "$(readlink "$ASSETS_PATH" 2>/dev/null || true)" != "$BAKED_PATH" ]; then
	if [ -d "$ASSETS_PATH" ] && [ ! -L "$ASSETS_PATH" ]; then
		rm -rf "$ASSETS_PATH"
	fi
	tmp="$SITES/.assets.$$"
	ln -sfn "$BAKED_PATH" "$tmp"
	mv -Tf "$tmp" "$ASSETS_PATH"
fi

exec "$@"
