## ADDED Requirements

### Requirement: KRO ResourceGraphDefinition for platform
The platform SHALL define a top-level KRO ResourceGraphDefinition that composes all AWS resources (RDS, ECR, CloudFront, WAF, Route 53, StorageClass, IngressClassParams, External Secrets) into a single deployable instance per environment.

#### Scenario: Single instance creates all platform resources
- **WHEN** a user applies a KRO instance YAML with `kind: OntoserverPlatform` specifying environment name and configuration
- **THEN** KRO orchestrates creation of all composed resources in dependency order

#### Scenario: Deleting the instance cascades cleanup
- **WHEN** a user deletes the KRO instance
- **THEN** all composed AWS resources (RDS, ECR repo, CloudFront distribution, WAF WebACL, Route 53 records) are deleted by ACK

### Requirement: RDS PostgreSQL via ACK
The platform SHALL provision an RDS PostgreSQL instance using the ACK rds-controller, with configurable instance class defaulting to `db.t4g.small`.

#### Scenario: Database provisioned
- **WHEN** the KRO instance is created
- **THEN** an RDS PostgreSQL instance is created in the cluster's VPC private subnets with encryption enabled, a security group allowing access from the EKS cluster, and the configured instance class

#### Scenario: Master credentials stored as K8s Secret
- **WHEN** the RDS instance reaches `available` state
- **THEN** ACK creates a Kubernetes Secret containing the database endpoint, port, username, and password

#### Scenario: Instance class switch documented
- **WHEN** a user changes the instance class parameter in the KRO instance
- **THEN** ACK triggers an RDS modification (with apply-immediately or during maintenance window as configured)

### Requirement: ECR pull-through cache via ACK
The platform SHALL configure an ECR pull-through cache rule for `quay.io` so that Ontoserver images are cached locally in the AWS account.

#### Scenario: Pull-through cache rule created
- **WHEN** the KRO instance is created
- **THEN** an ECR pull-through cache rule exists mapping `quay.io` to a local ECR prefix

#### Scenario: Image pull uses ECR cache
- **WHEN** a pod references an image via the ECR pull-through path (e.g., `<account>.dkr.ecr.<region>.amazonaws.com/quay.io/aehrc/ontoserver:ctsa-6`)
- **THEN** the image is served from ECR (cached or pulled-through from quay.io)

### Requirement: CloudFront CDN via ACK
The platform SHALL provision a CloudFront distribution fronting the ALB origin, using the ACK cloudfront-controller (Preview).

#### Scenario: CloudFront distribution created
- **WHEN** the KRO instance is created with CDN enabled
- **THEN** a CloudFront distribution is created with the ALB as origin, caching enabled, and HTTPS enforced

#### Scenario: CDN optional
- **WHEN** the KRO instance sets `cdn.enabled = false`
- **THEN** no CloudFront distribution is created and the ALB is accessed directly

### Requirement: WAF via ACK
The platform SHALL provision an AWS WAF WebACL attached to the ALB or CloudFront, using the ACK wafv2-controller.

#### Scenario: WAF WebACL attached
- **WHEN** the KRO instance is created with WAF enabled
- **THEN** a WAF WebACL with AWS managed rule groups (Core, Known Bad Inputs) is created and associated with the ingress resource

#### Scenario: Request body size accommodated
- **WHEN** a FHIR request with a body larger than 8 KB is sent (e.g., uploading a large CodeSystem)
- **THEN** the WAF rule allows it through (body size inspection limit configured appropriately or body inspection disabled for the upload paths)

### Requirement: Route 53 DNS via ACK
The platform SHALL create Route 53 DNS records pointing to the ALB or CloudFront distribution using the ACK route53-controller.

#### Scenario: DNS record created
- **WHEN** the KRO instance specifies a hosted zone and domain name
- **THEN** an A/ALIAS record is created in Route 53 pointing to the ALB or CloudFront domain

### Requirement: StorageClass for EBS gp3
The platform SHALL create a StorageClass for gp3 EBS volumes with tagging via `tagSpecification` parameters (layer 4 of 5-layer tagging).

#### Scenario: Tagged StorageClass available
- **WHEN** the platform resources are applied
- **THEN** a StorageClass named `ontoserver-gp3` exists with `provisioner: ebs.csi.aws.com`, `type: gp3`, `encrypted: "true"`, and tag specifications carrying Project/Environment/ManagedBy tags

### Requirement: IngressClassParams for ALB tagging
The platform SHALL create IngressClassParams with `spec.tags` carrying the required tag set (layer 5 of 5-layer tagging).

#### Scenario: ALB resources tagged
- **WHEN** an Ingress resource references the IngressClass backed by these params
- **THEN** the ALB, target groups, and listeners carry Project/Environment/ManagedBy tags

### Requirement: External Secrets Operator with ClusterSecretStore
The platform SHALL install External Secrets Operator and configure a ClusterSecretStore pointing to AWS Secrets Manager, using EKS Pod Identity for authentication.

#### Scenario: ClusterSecretStore functional
- **WHEN** an ExternalSecret referencing an AWS Secrets Manager key is created
- **THEN** ESO retrieves the secret value and creates/updates the target Kubernetes Secret

### Requirement: Custom NodeClass for tagging (layer 3)
The platform SHALL create a custom NodeClass with `spec.tags` carrying the required tag set, and a NodePool referencing it (layer 3 of 5-layer tagging). The default NodePool/NodeClass SHALL NOT be modified.

#### Scenario: New instances tagged
- **WHEN** EKS Auto Mode launches a new EC2 instance for a pod scheduled on the custom NodePool
- **THEN** the instance, root EBS volume, and ENIs carry Project/Environment/ManagedBy tags

### Requirement: Tag propagation documentation
The platform SHALL include documentation explaining how to extend the tag set and what each layer covers.

#### Scenario: User adds a custom tag
- **WHEN** a user adds a new tag key to the variables and applies the platform resources
- **THEN** the new tag appears on all future resources across all 5 layers
