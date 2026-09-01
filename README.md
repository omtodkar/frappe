# Cloud Local Frappe image

Reusable **Frappe-framework-only** image for Cloud Local and the projects that
build on it. Published as `ghcr.io/omtodkar/frappe` for `linux/amd64` and
`linux/arm64`.

It contains the Frappe framework, its Python environment, the front-end assets,
nginx, and the PostgreSQL client library. It contains **no ERPNext**, no project
application, no site, and no credential.

Project images derive from it:

```Dockerfile
FROM ghcr.io/omtodkar/frappe:v16.32.0@sha256:...
# bench get-app <your app>
```

A change to a project application therefore never rebuilds this image.

See [docs/image-contract.md](docs/image-contract.md) for the exact contents,
build pins, the assertions the build makes about itself, and the release
process.
