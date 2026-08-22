## Why

Ontoserver customers on AWS have no self-contained deployment recipe. The existing `azure/` directory provides a complete Terraform-based AKS deployment, but there is no AWS equivalent. Customers must reverse-engineer patterns from `sparked-infrastructure` (an internal repo) or piece together the Helm chart examples manually. A turnkey `aws/` directory — using EKS Auto Mode and the managed EKS Capabilities (ACK, KRO, Argo CD) — gives customers a Kubernetes-native, low-maintenance path to running Ontoserver on AWS with minimal infrastructure expertise.

## What Changes

- Add `aws/` directory with a complete, self-contained AWS deployment for Ontoserver
- Minimal Terraform bootstrap: VPC + EKS Auto Mode cluster + IAM for EKS Capabilities
- EKS Capabilities (ACK, KRO, Argo CD) enabled as managed features — no self-installed controllers
- KRO ResourceGraphDefinitions composing: RDS PostgreSQL, ECR pull-through cache, CloudFront CDN, WAF, Route 53 DNS
- One top-level KRO instance per environment for cascading resource cleanup
- 5-layer tagging strategy for all resources (Terraform, cluster, NodeClass, StorageClass, IngressClassParams)
- ALB ingress with ACM TLS termination (Auto Mode built-in LB controller)
- Argo CD (EKS Capability) for GitOps deployment of platform resources and Ontoserver Helm release
- EBS gp3 persistence for Lucene indexes via Auto Mode's built-in EBS CSI
- External Secrets Operator with ClusterSecretStore → AWS Secrets Manager
- EKS Pod Identity for workload IAM
- Container Insights + CloudWatch Logs (Auto Mode defaults)
- Both read-write and read-only Ontoserver deployment patterns documented as KRO instances
- README with architecture diagram and step-by-step instructions
- Integration test: deploy, validate FHIR endpoint, upload CodeSystem, query, teardown

## Capabilities

### New Capabilities

- `aws-bootstrap`: Terraform module creating VPC, EKS Auto Mode cluster, IAM roles, and enabling EKS Capabilities (ACK, KRO, Argo CD). Supports new or existing VPC. Implements 5-layer tagging.
- `aws-platform`: KRO ResourceGraphDefinitions composing ACK resources (RDS, ECR, CloudFront, WAF, Route 53) into a single per-environment instance. Includes StorageClass, IngressClassParams, and External Secrets configuration.
- `aws-deployment`: Argo CD Application definitions deploying the ontoserver Helm chart with EKS-specific values (ALB ingress, ACM TLS, EBS persistence, Pod Identity, RDS connection). Covers read-write and scaled read-only patterns.
- `aws-testing`: Integration test suite — deploy to live AWS account, validate FHIR endpoints with TLS, upload/query a CodeSystem, verify tagging, clean teardown.

### Modified Capabilities

(none — no existing specs)

## Impact

- New `aws/` directory tree (bootstrap/, platform/, deployment/, docs/)
- No changes to existing charts, azure/, docker/, or examples/ directories
- CI may gain an optional integration-test workflow gated on AWS credentials
- README.md top-level table gains an `aws/` row
