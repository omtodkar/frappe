# Cloud Local reusable Frappe base image.
#
# Frappe framework ONLY. This image deliberately contains no ERPNext and no
# project application: project images derive FROM this one and add their own
# apps, so a project app change never rebuilds this artifact.
#
# Everything that determines the artifact is pinned:
#   * the Python base image by digest
#   * Frappe by release TAG, asserted against its expected commit
#   * frappe-bench, Node, nvm and wkhtmltopdf by version
#
# The build asserts what it produced rather than trusting the recipe: the
# Frappe commit, the reported framework version, and — load-bearing for the
# "Frappe-only" claim — that exactly one app is installed and it is `frappe`.

ARG PYTHON_BASE=python:3.14-slim-bookworm@sha256:9ab8d9c8514b44f90cf0029dd42fdd7e9e211e639c8b995304cc04568dee900f

FROM ${PYTHON_BASE} AS base

ARG NODE_VERSION=24
ARG NVM_VERSION=v0.40.6
ARG YARN_VERSION=1.22.22
ARG WKHTMLTOPDF_VERSION=0.12.6.1-3
ARG WKHTMLTOPDF_DISTRO=bookworm
ARG BENCH_VERSION=5.31.0

ENV NVM_DIR=/home/frappe/.nvm
ENV NVM_SYMLINK_CURRENT=true
ENV PATH=${NVM_DIR}/current/bin/:${PATH}
ENV PYTHONUNBUFFERED=1

# bash with pipefail, so a failed curl piped into bash (the nvm install) fails
# the build instead of silently producing an image with no Node. Inherited by
# every stage built FROM this one.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# hadolint ignore=DL3008
RUN useradd -ms /bin/bash frappe \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    ca-certificates \
    curl \
    git \
    nginx \
    gettext-base \
    file \
    less \
    jq \
    media-types \
    # WeasyPrint runtime
    libpango-1.0-0 \
    libharfbuzz0b \
    libpangoft2-1.0-0 \
    libpangocairo-1.0-0 \
    # PostgreSQL client + libpq (this image is the PostgreSQL lane's runtime)
    libpq-dev \
    postgresql-client \
    # Frappe's pyproject depends on mysqlclient UNCONDITIONALLY, so the
    # MariaDB client library is required even though this lane speaks only
    # PostgreSQL. Runtime shared object here; headers in the build stage.
    libmariadb3 \
    # Node via nvm
    && mkdir -p ${NVM_DIR} \
    && curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash \
    && . ${NVM_DIR}/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm use ${NODE_VERSION} \
    && npm install -g "yarn@${YARN_VERSION}" \
    && nvm alias default ${NODE_VERSION} \
    && rm -rf ${NVM_DIR}/.cache \
    # wkhtmltopdf with patched Qt — Frappe's DEFAULT pdf_generator.
    # The `chrome` generator is deliberately NOT installed; a project needing
    # it layers chromium-headless-shell on top of this image.
    && if [ "$(uname -m)" = "aarch64" ]; then ARCH=arm64; else ARCH=amd64; fi \
    && wkhtmltox_deb="wkhtmltox_${WKHTMLTOPDF_VERSION}.${WKHTMLTOPDF_DISTRO}_${ARCH}.deb" \
    && curl -fsSLO "https://github.com/wkhtmltopdf/packaging/releases/download/${WKHTMLTOPDF_VERSION}/${wkhtmltox_deb}" \
    && apt-get install --no-install-recommends -y "./${wkhtmltox_deb}" \
    && rm "${wkhtmltox_deb}" \
    && pip3 install --no-cache-dir "frappe-bench==${BENCH_VERSION}" \
    && rm -rf /var/lib/apt/lists/* \
    # nginx as a non-root user, logging to stdout/stderr
    && rm -fr /etc/nginx/sites-enabled/default \
    && mkdir -p /etc/nginx/snippets \
    && sed -i '/user www-data/d' /etc/nginx/nginx.conf \
    && ln -sf /dev/stdout /var/log/nginx/access.log \
    && ln -sf /dev/stderr /var/log/nginx/error.log \
    && touch /run/nginx.pid \
    && chown -R frappe:frappe /etc/nginx/conf.d /etc/nginx/nginx.conf /etc/nginx/snippets \
    /var/log/nginx /var/lib/nginx /run/nginx.pid

COPY resources/nginx/frappe.conf.template /templates/nginx/frappe.conf.template
COPY resources/nginx/security_headers.conf /etc/nginx/snippets/security_headers.conf
COPY resources/nginx/nginx-entrypoint.sh /usr/local/bin/nginx-entrypoint.sh
COPY resources/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/nginx-entrypoint.sh /usr/local/bin/entrypoint.sh


FROM base AS build

# Build-only toolchain. None of this reaches the published image.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install --no-install-recommends -y \
    build-essential \
    gcc \
    pkg-config \
    wget \
    libbz2-dev \
    libffi-dev \
    liblcms2-dev \
    libldap2-dev \
    libmariadb-dev \
    libsasl2-dev \
    libtiff5-dev \
    libwebp-dev \
    tk8.6-dev \
    && rm -rf /var/lib/apt/lists/*

USER frappe

ARG FRAPPE_VERSION=v16.32.0
ARG FRAPPE_COMMIT=5cba016e86b54b57f34a3864282b92300ef20fb0
ARG FRAPPE_REPO=https://github.com/frappe/frappe

RUN bench init \
    --frappe-branch="${FRAPPE_VERSION}" \
    --frappe-path="${FRAPPE_REPO}" \
    --no-procfile \
    --no-backups \
    --skip-redis-config-generation \
    --verbose \
    /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

# Assert we built the commit we intended, while the .git directory that proves
# it still exists -- this is the only moment the evidence is available.
RUN got="$(git -C apps/frappe rev-parse HEAD)" \
    && if [ "${got}" != "${FRAPPE_COMMIT}" ]; then \
    echo "FATAL: frappe HEAD ${got} != expected ${FRAPPE_COMMIT}" >&2; exit 1; \
    fi \
    && echo "{}" > sites/common_site_config.json \
    && find apps -mindepth 1 -path "*/.git" -prune -exec rm -rf {} +


FROM base AS frappe

# Repeated rather than inherited: hadolint evaluates SHELL per stage, and this
# stage pipes. ENTRYPOINT/CMD below are exec form, so this has no runtime
# effect.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

USER frappe

COPY --from=build --chown=frappe:frappe /home/frappe/frappe-bench /home/frappe/frappe-bench

WORKDIR /home/frappe/frappe-bench

# Assets move to image-layer storage; the entrypoint links them back into the
# sites volume, which is a mount point at runtime and would otherwise shadow
# them.
RUN cp -r /home/frappe/frappe-bench/sites/assets /home/frappe/frappe-bench/assets \
    && rm -rf /home/frappe/frappe-bench/sites/assets \
    # A pristine copy of the sites skeleton OUTSIDE the mount point. A
    # Kubernetes PVC mounts empty over sites/ and hides apps.txt, which makes
    # bench unusable; the entrypoint restores it from here.
    && cp -a /home/frappe/frappe-bench/sites /home/frappe/frappe-bench/sites-seed \
    # The "Frappe-only" guarantee, asserted rather than assumed.
    && apps="$(tr -d '\r' < sites/apps.txt | grep -c . || true)" \
    && if [ "${apps}" != "1" ] || ! grep -qx 'frappe' sites/apps.txt; then \
    echo "FATAL: expected exactly one app 'frappe', got:" >&2; cat sites/apps.txt >&2; exit 1; \
    fi \
    && test ! -d apps/erpnext \
    && ./env/bin/python -c "import frappe, sys; sys.exit(0 if frappe.__version__.startswith('16.') else 1)"

VOLUME [ "/home/frappe/frappe-bench/sites", "/home/frappe/frappe-bench/logs" ]

ARG FRAPPE_VERSION=v16.32.0
ARG FRAPPE_COMMIT=5cba016e86b54b57f34a3864282b92300ef20fb0
LABEL org.opencontainers.image.title="Cloud Local Frappe" \
    org.opencontainers.image.description="Frappe framework only, no ERPNext, no project apps" \
    org.opencontainers.image.source="https://github.com/omtodkar/frappe" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.version="${FRAPPE_VERSION}" \
    io.cloudlocal.frappe.commit="${FRAPPE_COMMIT}"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["bench", "--help"]
