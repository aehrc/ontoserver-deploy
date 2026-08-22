## ADDED Requirements

### Requirement: Argo CD Application for Ontoserver
The deployment SHALL define an Argo CD Application (or ApplicationSet) that deploys the `ontoserver` Helm chart from the ontoserver-deploy repository with EKS-specific values.

#### Scenario: Ontoserver deployed via Argo CD
- **WHEN** the Argo CD capability syncs the Application
- **THEN** the Ontoserver Helm release is installed in the target namespace with the configured values

#### Scenario: Values updated via Git
- **WHEN** a user commits a change to the Ontoserver values file in the Git repository
- **THEN** Argo CD detects the change and syncs the updated configuration to the cluster

### Requirement: ALB Ingress with ACM TLS
The deployment SHALL configure Ingress resources with `ingressClassName: alb` and annotations for ACM certificate ARN, enabling TLS termination at the ALB.

#### Scenario: HTTPS endpoint accessible
- **WHEN** the Ontoserver deployment is complete
- **THEN** the FHIR endpoint is accessible over HTTPS via the ALB using the ACM certificate

#### Scenario: HTTP redirected to HTTPS
- **WHEN** a client connects to the ALB on port 80
- **THEN** the request is redirected to HTTPS (port 443)

### Requirement: EBS persistence for Lucene indexes
The deployment SHALL request a PersistentVolumeClaim using the `ontoserver-gp3` StorageClass for Ontoserver's Lucene index files, defaulting to gp3 with configurable size.

#### Scenario: PVC provisioned
- **WHEN** the Ontoserver pod starts
- **THEN** a gp3 EBS volume is provisioned via the PVC and mounted at the Lucene index path

#### Scenario: Data survives pod restart
- **WHEN** the Ontoserver pod is restarted or rescheduled
- **THEN** the same EBS volume is reattached and indexes are preserved

### Requirement: RDS connection configuration
The deployment SHALL configure Ontoserver's JDBC connection to the RDS instance using the credentials from the K8s Secret created by ACK (or ESO if using Secrets Manager).

#### Scenario: Ontoserver connects to RDS
- **WHEN** Ontoserver starts
- **THEN** it connects to the RDS PostgreSQL instance using the endpoint and credentials from the referenced Secret

### Requirement: EKS Pod Identity
The deployment SHALL use EKS Pod Identity associations for any AWS API access required by Ontoserver pods (e.g., accessing Secrets Manager, S3 for syndication feeds).

#### Scenario: Pod Identity association
- **WHEN** the Ontoserver pod's service account is annotated for Pod Identity
- **THEN** the pod receives temporary AWS credentials scoped to the associated IAM role without IRSA OIDC setup

### Requirement: Read-write deployment pattern
The deployment SHALL include a KRO instance and values file for a single read-write Ontoserver suitable for content authoring and development.

#### Scenario: Read-write server accepts uploads
- **WHEN** the read-write instance is deployed
- **THEN** FHIR write operations (POST/PUT CodeSystem, ValueSet, ConceptMap) succeed

### Requirement: Scaled read-only deployment pattern
The deployment SHALL include a KRO instance and values file for a scaled read-only Ontoserver suitable for production terminology serving.

#### Scenario: Read-only replicas serve queries
- **WHEN** the read-only instance is deployed with `replicas: 3`
- **THEN** three Ontoserver pods are running and serving FHIR read operations behind the ALB

#### Scenario: Write operations rejected
- **WHEN** a client sends a FHIR write operation to the read-only instance
- **THEN** the server returns an appropriate error (405 or OperationOutcome)

### Requirement: Argo CD manages platform resources
The deployment SHALL include Argo CD Applications for the KRO ResourceGraphDefinitions and their instances, enabling GitOps for the entire platform layer.

#### Scenario: Platform resources synced from Git
- **WHEN** the KRO ResourceGraphDefinitions or instances are modified in Git
- **THEN** Argo CD syncs the changes to the cluster, triggering ACK reconciliation of underlying AWS resources

### Requirement: Git repository structure for Argo CD
The deployment SHALL define a Git repository structure compatible with Argo CD, containing platform manifests, KRO instances, and Helm values in a single source of truth.

#### Scenario: Fresh clone deployable
- **WHEN** a user clones the repository and points Argo CD at it
- **THEN** Argo CD can discover and sync all Applications without manual kubectl steps beyond the initial bootstrap
