# varnish-exporter

Custom Docker image combining [Varnish 7.7](https://varnish-cache.org/) with the
[prometheus_varnish_exporter](https://github.com/jonnenauha/prometheus_varnish_exporter) binary,
used as a sidecar in the `ontoserver-extras` Helm chart.

## Why a custom image?

There is no officially supported Prometheus exporter for Varnish. The
[jonnenauha/prometheus_varnish_exporter](https://github.com/jonnenauha/prometheus_varnish_exporter)
is the de-facto standard community exporter. It needs to run alongside the Varnish process
(same pod) to access Varnish's shared memory and management interface.

The image bundles both Varnish and the exporter binary so that both containers in the pod can
use a single image — the main container overrides the entrypoint to run `varnishd`, and the
sidecar uses the default entrypoint to run the exporter.

## Image

```
ghcr.io/aehrc/varnish-exporter:7.7-1
```

Tag format: `<varnish-version>-<build-revision>`

Published release images are multi-arch and include:

- `linux/amd64` for AKS and other standard x86_64 Kubernetes worker nodes
- `linux/arm64` for local Apple Silicon development and ARM Kubernetes nodes

## Build and release

### Local build on Apple Silicon Mac

Build a local image you can run on your Mac:

```bash
docker buildx build \
  --platform linux/arm64 \
  -t ghcr.io/aehrc/varnish-exporter:7.7-1 \
  --load \
  docker/varnish-exporter
```

### Multi-arch release build

Build and push a multi-arch manifest for both `amd64` and `arm64`:

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t ghcr.io/aehrc/varnish-exporter:7.7-1 \
  -t ghcr.io/aehrc/varnish-exporter:latest \
  --push \
  docker/varnish-exporter
```

### GitHub Actions release

The repository includes a dedicated multi-arch release workflow in
`/.github/workflows/release-varnish-exporter.yml`.

Pushing a tag named `varnish-exporter-v<version>` publishes both `linux/amd64` and
`linux/arm64` images to GHCR and updates `latest`.

Example:

```bash
git tag varnish-exporter-v7.7-1
git push origin varnish-exporter-v7.7-1
```

## Components

| Component | Version |
|-----------|---------|
| [Varnish](https://varnish-cache.org/) | 7.7 |
| [prometheus_varnish_exporter](https://github.com/jonnenauha/prometheus_varnish_exporter) | 1.6.1 |
| Go builder | 1.18 |

## Ports

| Port | Description |
|------|-------------|
| 9131 | Prometheus metrics (`/metrics`) |

## Usage in ontoserver-extras

This image is referenced by the `ontoserver-extras` chart via `varnish.exporterImage`.
See the [ontoserver-extras chart](../ontoserver-extras/README.md) for full configuration.
