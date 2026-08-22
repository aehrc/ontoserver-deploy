## 1. Bootstrap — Terraform State Backend

- [ ] 1.1 Create `aws/bootstrap/state/` directory with Terraform config for S3 state bucket + DynamoDB lock table
- [ ] 1.2 Create helper script `aws/bootstrap/state/create-state-backend.sh` that provisions the backend resources
- [ ] 1.3 Add variables for region, project name, and environment
- [ ] 1.4 Test: run script, verify bucket exists with versioning and encryption enabled

## 2. Bootstrap — VPC and Networking

- [ ] 2.1 Create `aws/bootstrap/main.tf` with azurerm→aws provider, S3 backend configuration
- [ ] 2.2 Create `aws/bootstrap/vpc.tf` using `terraform-aws-modules/vpc/aws` with public/private subnets across 3 AZs, NAT Gateway
- [ ] 2.3 Add conditional VPC creation: skip if `vpc_id` variable is provided, look up subnets via data sources
- [ ] 2.4 Create `aws/bootstrap/variables.tf` with region, environment, kubernetes_version, vpc_cidr, vpc_id (optional), tags
- [ ] 2.5 Create `aws/bootstrap/outputs.tf` exporting cluster name, endpoint, VPC ID, subnet IDs
- [ ] 2.6 Add `default_tags` to provider block with Project, Environment, ManagedBy tags

## 3. Bootstrap — EKS Auto Mode Cluster

- [ ] 3.1 Create `aws/bootstrap/eks.tf` using `terraform-aws-modules/eks/aws` with Auto Mode enabled (`cluster_compute_config = { enabled = true }`)
- [ ] 3.2 Pin Kubernetes version via variable (default `1.32`)
- [ ] 3.3 Set `endpoint_public_access = true`
- [ ] 3.4 Add `enable_auto_mode_custom_tags = true` for custom tag key permissions
- [ ] 3.5 Add `cluster_tags` for the EKS primary security group (layer 2)
- [ ] 3.6 Configure access entries for the deploying user/role
- [ ] 3.7 Test: `terraform apply`, verify cluster is Active with Auto Mode, `kubectl get nodes` shows auto-provisioned nodes when pods are scheduled

## 4. Bootstrap — EKS Capabilities Enablement

- [ ] 4.1 Create `aws/bootstrap/capabilities.tf` with ACK capability resource (IAM role scoped to RDS, ECR, CloudFront, WAFv2, Route 53)
- [ ] 4.2 Add KRO capability resource
- [ ] 4.3 Add Argo CD capability resource
- [ ] 4.4 Create IAM policy documents for ACK capability role (least-privilege for each service)
- [ ] 4.5 Test: verify capabilities are Active (`aws eks describe-capability`), KRO CRDs available, Argo CD UI accessible

## 5. Platform — KRO ResourceGraphDefinition

- [ ] 5.1 Create `aws/platform/kro/ontoserver-platform-rgd.yaml` defining the top-level `OntoserverPlatform` ResourceGraphDefinition with schema (environment, region, db config, cdn enabled, waf enabled, domain, tags)
- [ ] 5.2 Define RDS DBInstance and DBSubnetGroup ACK resources within the RGD with CEL expressions for dependency wiring
- [ ] 5.3 Define ECR PullThroughCacheRule ACK resource within the RGD
- [ ] 5.4 Define CloudFront Distribution ACK resource (conditional on `cdn.enabled`) within the RGD
- [ ] 5.5 Define WAFv2 WebACL ACK resource (conditional on `waf.enabled`) within the RGD
- [ ] 5.6 Define Route 53 RecordSet ACK resource within the RGD
- [ ] 5.7 Define StorageClass with `tagSpecification` parameters (layer 4) within the RGD
- [ ] 5.8 Define IngressClassParams with `spec.tags` (layer 5) within the RGD
- [ ] 5.9 Define custom NodeClass + NodePool with `spec.tags` (layer 3) within the RGD
- [ ] 5.10 Define ESO ClusterSecretStore resource within the RGD
- [ ] 5.11 Test: apply RGD, verify CRD `ontoserverplatforms.kro.run` is registered, create a dry-run instance

## 6. Platform — KRO Instance (dev)

- [ ] 6.1 Create `aws/platform/instances/dev.yaml` with concrete values for a dev environment (db.t4g.small, 20GB EBS, cdn disabled, waf disabled)
- [ ] 6.2 Include all required tags in the instance spec
- [ ] 6.3 Test: apply instance, verify ACK creates RDS instance, ECR rule, StorageClass, NodeClass all in expected state

## 7. Deployment — Argo CD Applications

- [ ] 7.1 Create `aws/deployment/apps/platform.yaml` — Argo CD Application pointing to `aws/platform/kro/` for RGD definitions
- [ ] 7.2 Create `aws/deployment/apps/platform-instance.yaml` — Argo CD Application pointing to `aws/platform/instances/` for the environment instance
- [ ] 7.3 Create `aws/deployment/apps/ontoserver-rw.yaml` — Argo CD Application deploying ontoserver Helm chart with read-write values
- [ ] 7.4 Create `aws/deployment/apps/ontoserver-ro.yaml` — Argo CD Application deploying ontoserver Helm chart with scaled read-only values
- [ ] 7.5 Create `aws/deployment/apps/root.yaml` — app-of-apps pointing to the apps directory
- [ ] 7.6 Test: `kubectl apply -f root.yaml`, verify Argo CD syncs all applications

## 8. Deployment — Helm Values Files

- [ ] 8.1 Create `aws/deployment/values/ontoserver-rw.yaml` with: ALB ingress, ACM cert ARN annotation, gp3 PVC, RDS connection from Secret, Pod Identity SA annotation, single read-write instance
- [ ] 8.2 Create `aws/deployment/values/ontoserver-ro.yaml` with: ALB ingress, ACM cert ARN, gp3 PVC (ReadOnlyMany or shared index strategy), RDS connection, Pod Identity, replicas=3, isReadOnly=true
- [ ] 8.3 Validate both values files render cleanly: `helm template ontoserver ./charts/ontoserver -f <values>`
- [ ] 8.4 Test: deploy read-write instance, verify pod Running, healthcheck passing, FHIR metadata endpoint returns 200

## 9. Tagging — Verification

- [ ] 9.1 Create `aws/testing/scripts/verify-tags.sh` that checks all 5 layers: TF resources, cluster SG, EC2 instances, EBS volumes, ALBs
- [ ] 9.2 Test: run script against deployed environment, verify all resources carry expected tags

## 10. Testing — Integration Test Suite

- [ ] 10.1 Create `aws/testing/README.md` documenting test prerequisites, modes (full/test-only), and execution
- [ ] 10.2 Create `aws/testing/scripts/deploy.sh` — orchestrates full deploy (terraform apply + wait for capabilities + apply root app + wait for sync)
- [ ] 10.3 Create `aws/testing/scripts/validate.sh` — runs FHIR endpoint tests (metadata, upload CodeSystem, query, expand ValueSet)
- [ ] 10.4 Create `aws/testing/scripts/teardown.sh` — deletes Argo CD apps, waits for KRO cleanup, runs terraform destroy
- [ ] 10.5 Create `aws/testing/scripts/audit-orphans.sh` — queries AWS for any resources with test tags remaining after teardown
- [ ] 10.6 Create `aws/testing/fixtures/test-codesystem.json` — small CodeSystem for upload validation
- [ ] 10.7 Test: run full integration cycle (deploy → validate → teardown → audit), all steps pass

## 11. Documentation

- [ ] 11.1 Create `aws/README.md` with architecture diagram, prerequisites, step-by-step deployment guide, teardown instructions, cost notes
- [ ] 11.2 Create `aws/docs/architecture.md` with detailed component diagram and data flow
- [ ] 11.3 Create `aws/docs/tagging.md` explaining the 5-layer pattern and how to extend
- [ ] 11.4 Create `aws/docs/customisation.md` documenting switches: instance class, storage size/type, CDN, WAF, custom VPC, read-write vs read-only
- [ ] 11.5 Update top-level `README.md` to add `aws/` row to the directory table
- [ ] 11.6 Review: documentation is sufficient for a customer unfamiliar with EKS to deploy Ontoserver

## 12. CI Integration

- [ ] 12.1 Create `.github/workflows/aws-integration-tests.yml` (manual trigger or on push to `aws/` paths, gated on AWS credential secrets)
- [ ] 12.2 Add Terraform validation step (`terraform validate`, `terraform fmt --check`)
- [ ] 12.3 Add KRO manifest validation step (dry-run apply with `--dry-run=server`)
- [ ] 12.4 Add Helm template rendering step for the new values files (extend existing CI pattern)
