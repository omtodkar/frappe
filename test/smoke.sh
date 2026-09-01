#!/bin/bash
# Image smoke test. Asserts what the image IS, not that a build command
# succeeded: a build can succeed and still ship the wrong Frappe, an extra
# app, or a missing runtime dependency.
set -euo pipefail

fail=0
check() {
	local label="$1"; shift
	if "$@" >/dev/null 2>&1; then
		echo "PASS  ${label}"
	else
		echo "FAIL  ${label}"
		fail=1
	fi
}

cd /home/frappe/frappe-bench

echo "--- identity ---"
version="$(./env/bin/python -c 'import frappe; print(frappe.__version__)')"
echo "frappe.__version__ = ${version}"
case "${version}" in
	16.*) echo "PASS  frappe is a 16.x line" ;;
	*)    echo "FAIL  frappe is not 16.x"; fail=1 ;;
esac

echo "--- frappe-only guarantee ---"
echo "apps.txt:"; cat sites/apps.txt
app_count="$(grep -c . sites/apps.txt)"
[ "${app_count}" = "1" ] && echo "PASS  exactly one app" || { echo "FAIL  ${app_count} apps"; fail=1; }
grep -qx 'frappe' sites/apps.txt && echo "PASS  that app is frappe" || { echo "FAIL  app is not frappe"; fail=1; }
[ ! -d apps/erpnext ] && echo "PASS  no erpnext directory" || { echo "FAIL  erpnext present"; fail=1; }

echo "--- runtime dependencies ---"
check "psycopg2 imports (PostgreSQL driver)" ./env/bin/python -c 'import psycopg2'
check "redis client imports"                 ./env/bin/python -c 'import redis'
check "rq imports (background workers)"      ./env/bin/python -c 'import rq'
check "gunicorn present"                     ./env/bin/gunicorn --version
check "wkhtmltopdf present"                  wkhtmltopdf --version
check "node present"                         node --version
check "nginx binary present"                 nginx -v
check "bench present"                        bench --version

node_major="$(node --version | sed 's/^v\([0-9]*\).*/\1/')"
[ "${node_major}" -ge 24 ] && echo "PASS  node >= 24 (${node_major})" || { echo "FAIL  node ${node_major} < 24"; fail=1; }

echo "--- assets baked into the image layer ---"
[ -d /home/frappe/frappe-bench/assets/frappe ] \
	&& echo "PASS  assets/frappe exists in image layer" \
	|| { echo "FAIL  assets/frappe missing"; fail=1; }
[ -L /home/frappe/frappe-bench/sites/assets ] \
	&& echo "PASS  entrypoint linked sites/assets" \
	|| { echo "FAIL  sites/assets is not a symlink"; fail=1; }

echo "--- socketio entry point ---"
[ -f apps/frappe/socketio.js ] && echo "PASS  socketio.js present" || { echo "FAIL  socketio.js missing"; fail=1; }

echo "--- nginx template renders ---"
BACKEND=127.0.0.1:8000 SOCKETIO=127.0.0.1:9000 \
	timeout 5 /usr/local/bin/nginx-entrypoint.sh >/dev/null 2>&1 || true
if nginx -t -c /etc/nginx/nginx.conf >/dev/null 2>&1; then
	echo "PASS  rendered nginx config is valid"
else
	echo "FAIL  rendered nginx config is invalid"; nginx -t -c /etc/nginx/nginx.conf || true; fail=1
fi

echo "--- no credentials baked in ---"
if [ -s sites/common_site_config.json ] && [ "$(cat sites/common_site_config.json)" != "{}" ]; then
	echo "FAIL  common_site_config.json is not empty:"; cat sites/common_site_config.json; fail=1
else
	echo "PASS  common_site_config.json is empty"
fi
if find sites -name 'site_config.json' -o -name '*.key' -o -name '*.pem' 2>/dev/null | grep -q .; then
	echo "FAIL  credential-shaped files under sites/"; fail=1
else
	echo "PASS  no site_config.json / key / pem under sites/"
fi

echo
[ "${fail}" = "0" ] && echo "SMOKE: PASS" || echo "SMOKE: FAIL"
exit "${fail}"
