## Context

Ontoserver is a FHIR terminology server deployed via Helm charts in this repo. The existing `azure/` directory demonstrates infrastructure provisioning with Terraform targeting AKS. The `sparked-infrastructure` repo has an internal EKS deployment, but it's tightly coupled to CSIRO's account and not suitable for external customers.

EKS Auto Mode (GA since Dec 2024) shifts compute, storage, networking, and load balancing management to AWS. EKS Capabilities (ACK, KRO, Argo CD — all fully managed, running in EKS not on worker nodes) provide a Kubernetes-native GitOps platform without self-installed controllers.

The target audience is external Ontoserver customers who want to deploy on AWS with minimal Kubernetes expertise.

## Goals / Non-Goals

**Goals:**
- Self-contained `aws/` directory usable by external customers with no dependency on internal repos
- Minimal Terraform bootstrap (only chicken-and-egg resources)
- All application-layer AWS resources managed declaratively from within the cluster (ACK + KRO)
- GitOps via Argo CD (EKS Capability) — single source of truth in Git
- Clean teardown: delete KRO instance → cascading cleanup of all AWS resources; `terraform destroy` → removes cluster and networking
- 5-layer tagging for cost tracking and cleanup auditability
- Both read-write and read-only Ontoserver patterns
- Integration test validating end-to-end functionality including FHIR operations
- Documentation suitable for customers unfamiliar with EKS

**Non-Goals:**
- Multi-account or multi-cluster fleet management
- Production high-availability (multi-region, RDS Multi-AZ) — document as upgrade path only
- Custom node management — rely entirely on Auto Mode defaults
- Helm chart modifications — use existing `charts/ontoserver` as-is with values overrides
- CI/CD pipeline for the customer's application code (only infrastructure delivery)

## Decisions

### D1: EKS Auto Mode over standard EKS with Karpenter

**Choice:** EKS Auto Mode
**Rationale:** The target audience wants minimal ops. Auto Mode manages node lifecycle, AMI patching, scaling, EBS CSI, ALB controller, and VPC CNI with zero configuration. The sparked-infrastructure pattern (standard EKS + Karpenter + managed node groups + multiple addons) requires significantly more expertise.
**Alternative considered:** Standard EKS with EKS Blueprints addons — rejected due to operational complexity for external customers.

### D2: EKS Capabilities (managed ACK/KRO/Argo CD) over self-installed controllers

**Choice:** EKS Capabilities
**Rationale:** All three run in EKS (not on worker nodes), are fully managed by AWS (patching, scaling, availability), and require only an API call to enable. No Helm chart installation, no IRSA setup for controllers, no version pinning of controller images.
**Alternative considered:** Self-installed ACK via Helm + Flux — rejected because it defeats the "leave switches on Auto" principle and adds maintenance burden.

### D3: Argo CD (EKS Capability) for GitOps over Flux

**Choice:** Argo CD as EKS Capability
**Rationale:** Managed by AWS (zero maintenance), integrates with AWS Identity Center for auth, provides a hosted UI, and is designed to work with ACK + KRO. One Git repo is the source of truth. External customers get observability into sync state via the Argo UI without installing anything.
**Alternative considered:** Flux + CodeCommit — lighter weight but requires self-installation, and CodeCommit is deprecated for new customers.

### D4: Single top-level KRO instance per environment

**Choice:** One `OntoserverPlatform` ResourceGraphDefinition composing all AWS resources, instantiated once per environment.
**Rationale:** Maps to the Azure "Resource Group" mental model — delete the instance, everything goes away. Simplifies the customer's mental model: one YAML file = one environment. Sub-compositions (RDS, CDN, etc.) are internal implementation details within the RGD.
**Alternative considered:** Separate KRO instances per concern (DB, CDN, networking) — more flexible but harder to reason about for cleanup. Documented as an alternative for advanced users.

### D5: ACK CloudFront controller despite Preview status

**Choice:** Use the Preview ACK cloudfront-controller
**Rationale:** Maintains the K8s-native philosophy. CloudFront is optional (`cdn.enabled = false` by default). The Preview risk is acceptable for a CDN layer that can be replaced without data loss. Document the risk clearly.
**Alternative considered:** Terraform for CloudFront — breaks the single-plane-of-glass model. Could be added as a fallback if ACK proves unstable.

### D6: ALB with ACM for TLS over cert-manager

**Choice:** ALB terminates TLS using ACM certificate ARN annotations
**Rationale:** Simplest path on AWS. Auto Mode's built-in ALB controller handles provisioning. ACM certificates are free, auto-renewing, and don't require in-cluster certificate management. The existing chart README explicitly notes cert-manager is incompatible with ALB ingress class.
**Alternative considered:** cert-manager + Envoy Gateway — powerful but adds components the customer must maintain.

### D7: EKS Pod Identity over IRSA

**Choice:** EKS Pod Identity
**Rationale:** Newer, simpler mechanism. No OIDC provider setup required. Works with EKS Auto Mode natively. The bootstrap Terraform only needs to create Pod Identity associations (IAM role + service account binding) rather than OIDC configuration.
**Alternative considered:** IRSA — proven but requires OIDC provider and more complex IAM trust policies.

### D8: 5-layer tagging architecture

**Choice:** Implement all 5 layers with `enable_auto_mode_custom_tags = true`
**Rationale:** Without this, EC2 instances, EBS volumes, ALBs, and ENIs created by Auto Mode controllers are untagged. The IAM permission grant is a single flag on the EKS module. Customer can audit/delete by tag.
**Risk:** Layer 3 (NodeClass) requires a custom NodeClass — the managed `default` NodeClass cannot be patched (EKS silently reverts changes). We create a dedicated named NodeClass + NodePool.

### D9: Terraform for bootstrap only, not application resources

**Choice:** Terraform scope limited to: S3 state bucket, VPC, EKS cluster, IAM roles, EKS Capability enablement.
**Rationale:** Once the cluster exists with capabilities enabled, everything else is managed from within K8s via ACK/KRO/Argo CD. This gives a clean separation: `terraform destroy` removes infrastructure, `kubectl delete` removes application resources. Matches the customer mental model of "provision then configure."

## Risks / Trade-offs

**[KRO API stability]** → KRO is `v1alpha1`. ResourceGraphDefinition schema may change. Mitigation: pin KRO capability version; document that updates may require manifest changes. Since it's a managed capability, AWS handles the upgrade path.

**[ACK CloudFront Preview]** → Controller may have bugs or missing features. Mitigation: CDN is optional, off by default. Document the risk. Fall back to Varnish in-cluster caching (ontoserver-extras chart) if CloudFront proves problematic.

**[Cascading delete risk]** → Deleting the KRO instance deletes the RDS database. Mitigation: ACK supports `deletionPolicy: retain` on the DBInstance CR. Document this clearly. For production, recommend setting retain and taking a final snapshot.

**[EKS Auto Mode NodeClass restriction]** → Cannot patch the `default` NodeClass for tagging. Mitigation: Create a separate custom NodeClass. Workloads using the default NodePool will have untagged instances — acceptable for system pods, not for Ontoserver. Route Ontoserver to the custom NodePool via nodeSelector.

**[ACM certificate manual step]** → ACM certificates require DNS or email validation, which cannot be fully automated without existing Route 53 control. Mitigation: Document as a prerequisite. If Route 53 hosted zone exists, ACK can automate validation via DNS records.

**[EKS Capabilities pricing]** → Each capability incurs hourly charges. Mitigation: Document the cost. For dev/test, capabilities can be disabled when not in use. Provide cost estimate in README.

## Migration Plan

This is a net-new deployment (no migration from existing systems). Deployment order:

1. **Bootstrap** (Terraform): state bucket → VPC → EKS Auto Mode → IAM → enable capabilities
2. **Platform** (Argo CD syncs KRO definitions): ResourceGraphDefinitions applied → then instance created → ACK provisions RDS, ECR, etc.
3. **Deployment** (Argo CD syncs Ontoserver): Helm release installed with EKS values → pods scheduled → ALB provisioned → DNS record created

Teardown order (reverse):
1. Delete Ontoserver Argo CD Application (pods removed, ALB deleted)
2. Delete KRO instance (ACK deletes RDS, ECR, CloudFront, WAF, Route 53)
3. `terraform destroy` (EKS cluster, VPC, IAM removed)

## Open Questions

1. **ACK capability service scope**: Can a single ACK capability manage all required services (RDS, ECR, CloudFront, WAFv2, Route 53), or does each service need a separate capability enablement? Need to verify during implementation.
2. **Argo CD initial bootstrap**: How does the first Argo CD Application get applied if Argo CD manages everything? Likely needs a one-time `kubectl apply` of the root Application (app-of-apps pattern), after which Argo CD self-manages. Document this step.
3. **EBS volume lifecycle with Auto Mode**: If a node is replaced (21-day max lifetime), does the PVC volume reattach to the new node cleanly? Expected yes (standard K8s PVC behavior), but validate in testing.
4. **KRO + ACK tag propagation**: Can KRO pass tag values from the instance spec down to ACK resource specs automatically, or must each ACK resource in the RGD explicitly list tags? Likely explicit — validate.
