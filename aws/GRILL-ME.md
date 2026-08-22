# Grill-Me: AWS EKS Auto Mode Deployment for Ontoserver

Questions requiring your input before detailed specification begins.
Answers inline after each question — fill in and save.

---

## 1. Account & Environment

### 1.1 Single account or multi-account?
Will the EKS cluster and its backing services (RDS, ECR, CloudFront) all live in one AWS account, or do you want a multi-account setup where ACK creates resources cross-account via IAM role assumption?

**Answer:**

### 1.2 Region
Which AWS region? (The sparked-infrastructure pattern uses `ap-southeast-2`.)

**Answer:**

### 1.3 Environments
How many environments do we need to spec? (e.g., `dev` only for now, or `dev` + `prod`? The KRO instances directory can hold per-env configs.)

**Answer:**

### 1.4 Existing VPC or new?
Should the bootstrap Terraform create a new VPC, or should it expect an existing VPC (like sparked-infrastructure's sparkey-eks does)?

**Answer:**

---

## 2. EKS Auto Mode

### 2.1 Custom NodePools or purely default?
EKS Auto Mode creates a `default` NodePool. The Azure version has two node pools (a small one for system pods + a large one for Ontoserver). Do you want:
- (a) Purely default — let Auto Mode pick everything, or
- (b) One custom NodePool/NodeClass for Ontoserver workloads (to control instance family, e.g., memory-optimised for the 4G+ heap)?

**Answer:**

### 2.2 Kubernetes version pinning
Should the bootstrap pin a specific K8s version (e.g., `1.32`) or track latest?

**Answer:**

### 2.3 Private or public endpoint?
EKS API server endpoint: public, private, or both? (sparked-infrastructure uses `endpoint_public_access = true`.)

**Answer:**

---

## 3. Database

### 3.1 RDS instance class
The Azure version uses `B_Gen5_2` (basic tier, 2 vCPU). The sparked-infrastructure uses `db.t4g.small`. What sizing for this deployment?
- (a) `db.t4g.small` (2 vCPU, 2 GiB) — dev/test
- (b) `db.t4g.medium` (2 vCPU, 4 GiB) — production-like
- (c) Other

**Answer:**

### 3.2 RDS via ACK or bootstrap Terraform?
ACK's RDS controller is GA. Options:
- (a) ACK manages RDS (fully K8s-native, lifecycle tied to cluster) — preferred per your brief
- (b) Terraform manages RDS (independent lifecycle, survives cluster teardown)
- (c) Both supported — ACK for dev, Terraform for prod

Which approach? Note: if ACK manages RDS and you delete the K8s resource, the DB gets deleted too (unless deletion policy is set to `retain`).

**Answer:**

### 3.3 Database credentials
How should the DB password be managed?
- (a) ACK generates a master password stored in a K8s Secret
- (b) AWS Secrets Manager (with External Secrets Operator pulling it into K8s)
- (c) Something else

**Answer:**

---

## 4. Storage

### 4.1 Lucene index persistence
The Azure version uses a 512 GB Premium managed disk. EKS Auto Mode includes EBS CSI. Options:
- (a) gp3 PVC (what size? 512 GB like Azure, or smaller for initial dev?)
- (b) io2 for higher IOPS if indexing is time-sensitive

**Answer:**

### 4.2 EBS encryption
EKS Auto Mode encrypts by default. Use default AWS-managed key, or a customer-managed KMS key?

**Answer:**

---

## 5. Container Registry

### 5.1 ECR for Ontoserver images?
Azure version uses an optional ACR. Same pattern for ECR?
- (a) ECR pull-through cache for quay.io (what sparked-infrastructure uses)
- (b) Dedicated ECR repo where images are pushed manually
- (c) Pull directly from quay.io (no registry needed in AWS)

**Answer:**

---

## 6. Networking & Ingress

### 6.1 ALB Ingress class
EKS Auto Mode includes the AWS Load Balancer Controller. The existing EKS Helm examples use Envoy Gateway. Which do you want?
- (a) ALB Ingress (Auto Mode built-in) — simplest
- (b) Envoy Gateway (matching existing EKS Helm examples)
- (c) Both supported (Envoy for app routing, ALB for external ingress)

**Answer:**

### 6.2 TLS termination
- (a) ALB terminates TLS using ACM certificate (simplest for AWS)
- (b) cert-manager issues certs to Kubernetes Secrets (like Azure AGIC pattern)
- (c) Both — ALB with ACM for production, cert-manager for dev/local

Note from the existing README: "cert-manager is not compatible with `ingress.className: alb`". If ALB, TLS must use ACM certificate ARN annotations.

**Answer:**

### 6.3 DNS
Should the deployment include Route 53 record management?
- (a) Yes, ACK route53-controller creates DNS records
- (b) No, DNS is managed externally
- (c) ExternalDNS operator (watches Ingress annotations, creates Route 53 records)

**Answer:**

### 6.4 WAF
The Azure version has an optional WAF on the App Gateway. For AWS:
- (a) AWS WAF on ALB/CloudFront via ACK wafv2-controller
- (b) Skip WAF for now (add later)
- (c) Other

**Answer:**

---

## 7. CDN / Caching

### 7.1 CloudFront via ACK
The ACK cloudfront-controller exists but is in Preview (not GA). Options:
- (a) Use it anyway — accept Preview status, document the risk
- (b) Fall back to Terraform for CloudFront
- (c) Skip CDN for initial delivery, add later
- (d) Use Varnish in-cluster caching (the ontoserver-extras chart already supports this) instead of CloudFront

**Answer:**

---

## 8. Observability

### 8.1 Monitoring stack
EKS Auto Mode includes Container Insights. The sparked-infrastructure also deploys Prometheus. What do you want here?
- (a) Container Insights only (Auto Mode default, zero config)
- (b) Prometheus + Grafana (chart already supports `serviceMonitor`)
- (c) Both
- (d) OpenTelemetry (chart supports OTel instrumentation)

**Answer:**

### 8.2 Logging
- (a) CloudWatch Logs (Auto Mode default)
- (b) Something else (Loki, etc.)

**Answer:**

---

## 9. Tagging & Cleanup

### 9.1 Required tags
What tag keys should all resources carry? Suggested minimum:
- `Project` (e.g., `ontoserver`)
- `Environment` (e.g., `dev`, `prod`)
- `ManagedBy` (e.g., `terraform`, `ack`, `eks-auto-mode`)
- `auto-delete` or `TTL` (for dev environments that should auto-expire)

What keys/values do you want? Any org-mandated tags?

**Answer:**

### 9.2 5-layer tagging
EKS Auto Mode resources created by built-in controllers (EC2, EBS, ALB) require a [5-layer tagging pattern](https://aws-samples.github.io/sample-aws-eks-auto-mode/docs/architecture/tagging):
1. Terraform `default_tags` (VPC, EKS cluster, IAM)
2. EKS `cluster_tags` (primary security group)
3. Custom NodeClass `spec.tags` (EC2 instances, root volumes, ENIs)
4. StorageClass `tagSpecification` (PVC-provisioned EBS)
5. IngressClassParams `spec.tags` (ALBs, target groups)

This requires `enable_auto_mode_custom_tags = true` on the EKS module (adds IAM permissions for custom tag keys). Acceptable?

**Answer:**

### 9.3 KRO as resource grouping
You mentioned KRO ResourceGroups as an analogue to Azure Resource Groups for logical grouping + cascading cleanup. The KRO `ResourceGraphDefinition` composes resources, and deleting the instance triggers deletion of all composed resources.

Should we design:
- (a) One top-level KRO instance per environment (delete the instance = delete everything)
- (b) Separate KRO instances per concern (network, database, app) so they can be torn down independently
- (c) Hybrid — one master that references sub-compositions

**Answer:**

---

## 10. Secrets & Identity

### 10.1 Pod identity
EKS Auto Mode supports EKS Pod Identity (no IRSA setup needed). The chart already has `serviceAccount.annotations` for `eks.amazonaws.com/role-arn`. Which mechanism?
- (a) EKS Pod Identity (newer, simpler)
- (b) IRSA (existing pattern in sparked-infrastructure)
- (c) Either — support both

**Answer:**

### 10.2 External Secrets Operator
The ontoserver chart already supports External Secrets. Should the platform layer install ESO and configure a ClusterSecretStore pointing to AWS Secrets Manager?

**Answer:**

---

## 11. CI/CD & GitOps

### 11.1 ArgoCD or Flux?
The sparked-infrastructure uses ArgoCD (there's a `sparked-argo` repo). The examples directory has ArgoCD manifests. Use ArgoCD for deploying the ACK/KRO resources and Ontoserver?

**Answer:**

### 11.2 Terraform state backend
- (a) Reuse the existing `examplebucket-fhir-aws` S3 bucket (from sparked-infrastructure)
- (b) New dedicated state bucket for this project
- (c) To be determined when AWS account access is provided

**Answer:**

---

## 12. Testing

### 12.1 ct (chart-testing) relevance
`ct` validates Helm charts (yamllint, schema validation, maintainer check). It's relevant for:
- Any new Helm chart or overlay we add to `charts/`
- NOT directly relevant for Terraform or raw KRO manifests

However, if we package ACK controller installations or KRO ResourceGraphDefinitions as a Helm chart, ct would validate those. Should the ACK/KRO layer be:
- (a) Raw manifests (simpler, kustomize-friendly, ArgoCD-native)
- (b) Helm chart (ct-testable, version-tracked, parameterised)
- (c) Mix — ACK controllers via their official Helm charts, KRO compositions as raw manifests

**Answer:**

### 12.2 Integration test AWS account
Will the integration tests run against:
- (a) The same account you'll provide later
- (b) A dedicated CI account
- (c) TBD

**Answer:**

### 12.3 Acceptance test scope
For the integration test, what constitutes "working"?
- (a) Ontoserver pod Running + healthcheck passing
- (b) Full FHIR endpoint accessible via ALB with TLS
- (c) (b) + can upload a small CodeSystem and query it back
- (d) Other

**Answer:**

---

## 13. Scope & Priorities

### 13.1 MVP vs full parity
For the first deliverable, which services are must-have vs nice-to-have?

| Service | Must-have? |
|---------|-----------|
| EKS Auto Mode cluster | |
| VPC/networking | |
| RDS PostgreSQL | |
| EBS persistence (Lucene indexes) | |
| ALB ingress with TLS | |
| ECR | |
| CloudFront CDN | |
| WAF | |
| Monitoring/logging | |
| External Secrets | |

**Answer:**

### 13.2 Timeline pressure
Is there a deadline or event driving this, or is it spec-at-leisure?

**Answer:**

---

## 14. Open Questions from Me

### 14.1 KRO maturity
kro is described as "not yet intended for production use" (their README). The ResourceGraphDefinition API is `v1alpha1` and "highly subject to change." Are you comfortable with:
- (a) Using it knowing it may need rework when APIs stabilise
- (b) Want a fallback plan (e.g., Helm + ArgoCD without KRO for prod, KRO for dev)

**Answer:**

### 14.2 Ontoserver read-write vs read-only
The Azure version doesn't specify. The EKS examples show both patterns. Should the default deployment be:
- (a) Single read-write (simplest, for development/authoring)
- (b) Scaled read-only (production pattern, needs a separate write instance for content loading)
- (c) Both documented as KRO instances

**Answer:**

### 14.3 Relationship to sparked-infrastructure
Should this `aws/` directory be self-contained (duplicating VPC/EKS bootstrap), or should it reference/import from sparked-infrastructure? The Azure directory is self-contained.

**Answer:**

---

*End of grill-me. Save your answers and let me know when ready.*
