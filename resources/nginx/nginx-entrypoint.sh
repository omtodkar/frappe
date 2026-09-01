#!/bin/bash
# Renders the nginx template and execs nginx in the foreground.
set -eu

: "${BACKEND:=0.0.0.0:8000}"
: "${SOCKETIO:=0.0.0.0:9000}"
: "${UPSTREAM_REAL_IP_ADDRESS:=127.0.0.1}"
: "${UPSTREAM_REAL_IP_HEADER:=X-Forwarded-For}"
: "${UPSTREAM_REAL_IP_RECURSIVE:=off}"
: "${PROXY_READ_TIMEOUT:=120}"
: "${CLIENT_MAX_BODY_SIZE:=50m}"
# shellcheck disable=SC2016
: "${FRAPPE_SITE_NAME_HEADER:=\$host}"

export BACKEND SOCKETIO UPSTREAM_REAL_IP_ADDRESS UPSTREAM_REAL_IP_HEADER \
	UPSTREAM_REAL_IP_RECURSIVE PROXY_READ_TIMEOUT CLIENT_MAX_BODY_SIZE \
	FRAPPE_SITE_NAME_HEADER

# shellcheck disable=SC2016
envsubst '${BACKEND}
	${SOCKETIO}
	${UPSTREAM_REAL_IP_ADDRESS}
	${UPSTREAM_REAL_IP_HEADER}
	${UPSTREAM_REAL_IP_RECURSIVE}
	${FRAPPE_SITE_NAME_HEADER}
	${PROXY_READ_TIMEOUT}
	${CLIENT_MAX_BODY_SIZE}' \
	</templates/nginx/frappe.conf.template >/etc/nginx/conf.d/frappe.conf

exec nginx -g 'daemon off;'
