## ADDED Requirements

### Requirement: VPC creation
The bootstrap SHALL create a new VPC with public and private subnets across 3 Availability Zones in the configured region, with NAT Gateway for private subnet egress. The bootstrap SHALL accept an optional existing VPC ID to skip VPC creation.

#### Scenario: New VPC created by default
- **WHEN** the user runs `terraform apply` without providing an existing VPC ID
- **THEN** a new VPC is created with public subnets, private subnets, an Internet Gateway, and a NAT Gateway across 3 AZs

#### Scenario: Existing VPC provided
- **WHEN** the user provides a `vpc_id` variable
- **THEN** no new VPC is created and the EKS cluster uses the provided VPC's subnets

### Requirement: EKS Auto Mode cluster
The bootstrap SHALL create an EKS cluster with Auto Mode enabled, pinned to a specific Kubernetes version, with a public API server endpoint.

#### Scenario: Cluster creation with Auto Mode
- **WHEN** `terraform apply` completes successfully
- **THEN** an EKS cluster exists with `computeConfig.enabled = true`, `storageConfig.enabled = true`, `kubernetesNetworkConfig` set to Auto Mode defaults, and the specified Kubernetes version

#### Scenario: Kubernetes version pinning
- **WHEN** the user sets `kubernetes_version = "1.32"`
- **THEN** the EKS cluster control plane runs Kubernetes 1.32 and Auto Mode nodes use the corresponding AMI

### Requirement: EKS Capabilities enablement
The bootstrap SHALL enable all three EKS Capabilities (ACK, KRO, Argo CD) on the cluster with appropriate IAM roles.

#### Scenario: ACK capability created
- **WHEN** the cluster is provisioned
- **THEN** an ACK capability is active with IAM permissions for RDS, ECR, CloudFront, WAFv2, and Route 53

#### Scenario: KRO capability created
- **WHEN** the cluster is provisioned
- **THEN** a KRO capability is active and can reconcile ResourceGraphDefinition custom resources

#### Scenario: Argo CD capability created
- **WHEN** the cluster is provisioned
- **THEN** an Argo CD capability is active with a reachable Argo CD UI endpoint

### Requirement: IAM for EKS Capabilities
The bootstrap SHALL create IAM roles for each EKS Capability with least-privilege policies scoped to the services they manage.

#### Scenario: ACK capability role permissions
- **WHEN** ACK attempts to create an RDS instance, ECR repository, CloudFront distribution, WAF WebACL, or Route 53 record
- **THEN** the operation succeeds because the capability role has the necessary permissions

#### Scenario: Custom tag permissions
- **WHEN** Auto Mode controllers (Karpenter, EBS CSI, ALB controller) create resources with custom tag keys (Project, Environment, ManagedBy)
- **THEN** the operations succeed because `enable_auto_mode_custom_tags = true` adds the necessary IAM policy

### Requirement: 5-layer tagging (bootstrap layers)
The bootstrap SHALL implement layers 1 and 2 of the 5-layer tagging pattern: Terraform `default_tags` on all TF-created resources, and `cluster_tags` on the EKS primary security group.

#### Scenario: Terraform-created resources tagged
- **WHEN** any resource is created by Terraform (VPC, subnets, NAT, EKS cluster, IAM roles)
- **THEN** the resource carries tags: `Project`, `Environment`, `ManagedBy=terraform`

#### Scenario: EKS primary security group tagged
- **WHEN** the EKS cluster is created
- **THEN** the EKS-managed primary security group carries the same tag set via `cluster_tags`

### Requirement: Terraform state backend
The bootstrap SHALL use an S3 backend with DynamoDB locking for Terraform state. A helper script SHALL create the state bucket if it does not exist.

#### Scenario: State bucket creation
- **WHEN** the user runs the bootstrap setup script for the first time
- **THEN** an S3 bucket with versioning, encryption, and a DynamoDB lock table are created

#### Scenario: State locking
- **WHEN** two concurrent `terraform apply` runs target the same state
- **THEN** one is blocked by the DynamoDB lock until the other completes

### Requirement: Configurable variables
The bootstrap SHALL expose variables for: region, environment name, Kubernetes version, VPC CIDR, existing VPC ID (optional), and tag values.

#### Scenario: Minimal configuration
- **WHEN** the user provides only `environment = "dev"` and `region = "ap-southeast-2"`
- **THEN** all other variables use sensible defaults and the deployment succeeds
