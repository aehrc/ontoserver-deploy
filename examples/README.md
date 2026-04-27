# Ontoserver Deployment Examples

This directory contains examples for deploying and customising [Ontoserver](https://ontoserver.csiro.au/) across various environments and using different deployment tools.

## Deployment Scenarios

For infrastructure-specific configurations (AKS, EKS, local development), see the examples included within the Helm chart directory:

- [**AKS (Azure)**](../charts/ontoserver/examples/aks/) — Scaled production clusters, sidecar databases, and AGIC ingress.
- [**EKS (AWS)**](../charts/ontoserver/examples/eks/) — Scaled production clusters, RDS integration, and ALB ingress.
- [**Local Development**](../charts/ontoserver/examples/local/) — Quick-start configurations for k3d, minikube, and kind.
- [**Networking**](../charts/ontoserver/examples/networking/) — Detailed Gateway API, Ingress, and Traefik configurations.

## GitOps & Advanced Customisation

The following examples demonstrate how to integrate Ontoserver into broader GitOps workflows or apply advanced post-processing overrides:

- [**ArgoCD**](./argocd/) — Ready-to-use Application and ApplicationSet manifests, including multi-source examples for Varnish caching.
- [**Kustomize**](./kustomize/) — Post-processing examples, such as injecting a `priorityClassName` into the deployment.

---

> **Note:** When using a distributed version of the Helm chart (e.g. from a Helm repository), the examples in this `examples/` directory may not be included in the chart package. Always refer to the [main GitHub repository](https://github.com/aehrc/ontoserver-deploy) for the latest GitOps and post-processing examples.
