# Ontoserver deployment examples

This repository provides example deployment projects and infrastructure setup for [Ontoserver](https://ontoserver.csiro.au) using different technologies.

* [docker](docker/) - Deployment project using docker-compose files
* [helm](helm/) - Helm charts for Kubernetes deployments
* [azure](azure/) - Example infrastructure on Azure using Azure Kubernetes Services to host Ontoserver containers

You will find different configuration sets in the repository branches:
* [horizontal-scaling](https://github.com/aehrc/ontoserver-deploy/tree/horizontal-scaling) - Example docker deployment with horizontal scaling that deploys one read/write Ontoserver and multiple read only Ontoservers in a stack
* [horizontal-scaling-readonly-onto6](https://github.com/aehrc/ontoserver-deploy/tree/horizontal-scaling-readonly-onto6) - Example docker deployment with horizontal scaling that deploys multiple read only Ontoservers in a stack
* [preload-bundle](https://github.com/aehrc/ontoserver-deploy/tree/preload-bundle) - Example deployment including an embedded preload bundle to provide initial content for Ontoserver
* [preload-feed](https://github.com/aehrc/ontoserver-deploy/tree/preload-feed) - Example deployment including an embedded preload feed to provide initial content for Ontoserver