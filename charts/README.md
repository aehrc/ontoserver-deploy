# Helm Charts

This directory contains the maintained Helm charts published from this repository:

- [`ontoserver/`](./ontoserver/) - main Ontoserver chart
- [`ontoserver-extras/`](./ontoserver-extras/) - optional Varnish and OpenTelemetry components
- [`ontoserver-indexer/`](./ontoserver-indexer/) - one-shot indexing Job chart

## Releasing Charts

**See [`RELEASE.md`](../RELEASE.md) for the full process.** In short: charts are released by
**Release Please**, which opens one release PR per chart on every push to `master`. Merging that PR
tags, releases, and publishes the chart. You do not edit versions or changelogs by hand.

Which chart a commit releases is decided by the **file paths it touches**, not by the commit scope,
so keep a commit to one chart where you can.

Distribution:

```bash
helm repo add ontoserver https://aehrc.github.io/ontoserver-deploy
helm install my-ontoserver ontoserver/ontoserver -f your-values.yaml
```

`release.sh` and the tag-triggered `.github/workflows/release.yml` are retained for manual releases
and recovery only — note that `release.sh` still follows the **older** convention where `Chart.yaml`
holds the in-development version, so using it leaves `.release-please-manifest.json` out of step.
`RELEASE.md` covers both, plus recovery steps.
- the corresponding `ghcr.io` package visibility is set as intended

## Releasing Varnish Exporter

The Varnish exporter image is released separately from `.github/workflows/release-varnish-exporter.yml`.

Use a tag in this format:

- `varnish-exporter-vX.Y.Z`

That tag builds and publishes:

- `ghcr.io/aehrc/varnish-exporter`
