# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

### Added

- Initial public release of the `ontoserver-indexer` chart.
- A one-shot Kubernetes Job for indexing terminology content with the Ontoserver CLI.
- Support for SNOMED CT RF2 packages and LOINC distribution ZIP inputs.
- Support for reading input files from HTTPS locations or a mounted PVC.
- Support for publishing the generated archive to a syndication server, writing it to a PVC, or both.
- Support for OAuth2 client credentials or HTTP Basic authentication when publishing to the syndication server.
- Automatic creation of a pull secret for the default authenticated `quay.io/aehrc/ontoserver` image, with support for pre-existing image pull secrets as well.
- Controls for job naming, TTL cleanup, and scheduling on spot or preemptible node pools.

### Changed

- This initial `ontoserver-indexer` release was created when the repository was tagged for the released `ontoserver` `0.2.0` chart.
