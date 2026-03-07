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

## Build

```bash
docker build -t ghcr.io/aehrc/varnish-exporter:7.7-1 .
docker push ghcr.io/aehrc/varnish-exporter:7.7-1
```

The image is intended to be built and pushed automatically via GitHub Actions (see
`.github/workflows/` in this repository).

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
