# Frappe image contract

## What this image is

The Frappe **framework** and nothing else. It is the base layer for Cloud Local's
Frappe/PostgreSQL dev/staging lane and for project images that add their own
apps.

| | |
| --- | --- |
| Image | `ghcr.io/omtodkar/frappe` |
| Platforms | `linux/amd64`, `linux/arm64` |
| Frappe | `v16.32.0`, commit `5cba016e86b54b57f34a3864282b92300ef20fb0` |
| Python | 3.14 (`python:3.14-slim-bookworm`, digest pinned) |
| Node | 24 (via nvm `v0.40.6`) |
| bench | `frappe-bench==5.31.0` |
| wkhtmltopdf | `0.12.6.1-3` (bookworm, patched Qt) |

## What it deliberately does NOT contain

- **ERPNext.** The build fails if `apps/erpnext` exists.
- **Any project application.** The build fails unless `sites/apps.txt` holds
  exactly one line and that line is `frappe`.
- **Chromium.** Frappe v16 offers `wkhtmltopdf` (the default) and `chrome` as
  print generators. Only the default is installed; a project that needs the
  `chrome` generator layers `chromium-headless-shell` on top.
- **Any site, credential, or `site_config.json`.** `common_site_config.json` is
  `{}`.
- **The build toolchain.** `build-essential`, `gcc` and the `-dev` headers live
  in a separate stage that the published image does not inherit from.

## Determinism

Every input that decides the artifact is pinned: the base image by digest,
Frappe by release tag, and bench/Node/nvm/wkhtmltopdf by version. Debian package
versions are not pinned — that would break the build on each security update —
which is the same trade the sibling `omtodkar/postgres` image makes.

## The build asserts what it produced

A recipe that looks right can still ship the wrong artifact, so the build checks
the result rather than trusting the instructions:

1. **Frappe commit.** After `bench init`, `git rev-parse HEAD` in `apps/frappe`
   must equal the expected commit. Checked before the `.git` directories are
   removed, which is the only moment the evidence exists.
2. **Exactly one app, and it is `frappe`.** This is the whole "Frappe-only"
   guarantee; without it a transitively pulled dependency app would ship
   unnoticed.
3. **No `apps/erpnext` directory.**
4. **`frappe.__version__` starts with `16.`.**

`test/smoke.sh` then runs against the built image in CI and re-checks the above
from outside the build, plus: `psycopg2`, `redis` and `rq` import; gunicorn,
wkhtmltopdf, node ≥ 24, nginx and bench are present; the assets really are in
the image layer and the entrypoint links them into `sites/`; `socketio.js`
exists; the rendered nginx config passes `nginx -t`; and nothing
credential-shaped sits under `sites/`.

## Runtime shape

`ENTRYPOINT` links the image-layer assets back into `sites/assets`, because
`sites/` is a volume at runtime and would otherwise shadow them. The container
then execs whatever command it was given, so one image serves every role:

| Role | Command |
| --- | --- |
| gunicorn | `bench serve` / `gunicorn frappe.app:application` |
| worker | `bench worker --queue <queues>` |
| scheduler | `bench schedule` |
| socketio | `node apps/frappe/socketio.js` |
| nginx | `/usr/local/bin/nginx-entrypoint.sh` |

nginx runs as the unprivileged `frappe` user on port **8080** and is configured
by `BACKEND`, `SOCKETIO`, `FRAPPE_SITE_NAME_HEADER`, `PROXY_READ_TIMEOUT` and
`CLIENT_MAX_BODY_SIZE`.

## Release process

1. Pick the target Frappe release and record its **commit**.
2. Update `FRAPPE_VERSION` and `FRAPPE_COMMIT` in the `Dockerfile`, the
   `type=raw` tag in `.github/workflows/image.yml`, and the table above.
3. Push a `v16.*` tag. CI lints, builds each architecture on its own **native**
   runner, smoke-tests each, pushes by digest and merges one manifest list.
   Neither architecture is emulated: Frappe's front-end asset build is slow
   enough under QEMU to be a reliability problem.
4. Take the manifest-list digest from the job summary and pin it in GitOps.
