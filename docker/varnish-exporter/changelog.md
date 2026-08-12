# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [7.7-1]

### Added

- Initial public release of the `varnish-exporter` image.
- Multi-stage Docker build that compiles `github.com/jonnenauha/prometheus_varnish_exporter@1.6.1`.
- Runtime image based on `varnish:7.7`.
- Default entrypoint for running `prometheus_varnish_exporter` as a sidecar container.
- Port `9131` exposure for Prometheus metrics scraping.

### Changed

- This initial image definition already existed when the repository was tagged for the released `ontoserver` `0.2.0` chart, and there have been no Dockerfile changes since that tag.
