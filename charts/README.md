# Helm Charts

This directory contains the maintained Helm charts published from this repository:

- [`ontoserver/`](./ontoserver/) - main Ontoserver chart
- [`ontoserver-extras/`](./ontoserver-extras/) - optional Varnish and OpenTelemetry components
- [`ontoserver-indexer/`](./ontoserver-indexer/) - one-shot indexing Job chart

## Releasing Charts

Charts are released from Git tags via GitHub Actions.

Preferred distribution is the GitHub Pages Helm repository:

```bash
helm repo add ontoserver https://aehrc.github.io/ontoserver-deploy
```

Release tags must match the workflow triggers in `.github/workflows/release.yml`:

- `ontoserver-vX.Y.Z`
- `ontoserver-extras-vX.Y.Z`
- `ontoserver-indexer-vX.Y.Z`

Pushing one of those tags triggers the chart release workflow, which:

- publishes the chart to the GitHub Pages Helm repository via `chart-releaser-action`
- updates `artifacthub-repo.yml` on the `gh-pages` branch
- pushes the packaged chart to `ghcr.io/aehrc` as a secondary OCI artifact

Example:

```bash
git tag ontoserver-v0.1.0
git push origin ontoserver-v0.1.0
```

After the first release, confirm:

- GitHub Pages is enabled for the `gh-pages` branch
- the new chart version appears in the Helm repo index
- the corresponding `ghcr.io` package visibility is set as intended

## Releasing Varnish Exporter

The Varnish exporter image is released separately from `.github/workflows/release-varnish-exporter.yml`.

Use a tag in this format:

- `varnish-exporter-vX.Y.Z`

That tag builds and publishes:

- `ghcr.io/aehrc/varnish-exporter`
