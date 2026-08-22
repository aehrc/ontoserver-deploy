## ADDED Requirements

### Requirement: Integration test deploys full stack
The test suite SHALL deploy the complete stack (bootstrap + platform + deployment) to a live AWS account and validate end-to-end functionality.

#### Scenario: Full deployment succeeds
- **WHEN** the integration test pipeline runs against a configured AWS account
- **THEN** all resources (VPC, EKS, RDS, ECR, ALB, Ontoserver) are created and reach healthy state within a reasonable timeout (30 minutes)

### Requirement: FHIR endpoint validation
The test suite SHALL validate that the Ontoserver FHIR endpoint is accessible over HTTPS and returns valid FHIR responses.

#### Scenario: Capability statement accessible
- **WHEN** the test sends GET to `https://<endpoint>/fhir/metadata`
- **THEN** the response is HTTP 200 with a FHIR CapabilityStatement resource

#### Scenario: TLS certificate valid
- **WHEN** the test connects to the HTTPS endpoint
- **THEN** the TLS handshake succeeds with a valid certificate (no self-signed warnings)

### Requirement: CodeSystem upload and query
The test suite SHALL upload a small CodeSystem resource and verify it can be queried back.

#### Scenario: Upload CodeSystem
- **WHEN** the test POSTs a small CodeSystem (e.g., 10 codes) to the read-write instance
- **THEN** the server returns HTTP 201 Created with the resource ID

#### Scenario: Query CodeSystem
- **WHEN** the test sends GET to `/fhir/CodeSystem/<id>`
- **THEN** the response contains the uploaded CodeSystem with all codes intact

#### Scenario: ValueSet expansion
- **WHEN** the test sends a `$expand` operation on a ValueSet referencing the uploaded CodeSystem
- **THEN** the response contains an expanded ValueSet with the expected codes

### Requirement: Tagging audit
The test suite SHALL verify that all AWS resources carry the required tag set (Project, Environment, ManagedBy).

#### Scenario: Terraform-created resources tagged
- **WHEN** the test lists resources in the VPC and EKS cluster
- **THEN** all resources carry the expected tags

#### Scenario: ACK-created resources tagged
- **WHEN** the test inspects the RDS instance and ECR repository
- **THEN** they carry the expected tags (propagated from the KRO instance spec)

#### Scenario: Auto Mode-created resources tagged
- **WHEN** the test inspects EC2 instances, EBS volumes, and ALBs created by Auto Mode controllers
- **THEN** they carry the expected tags (from NodeClass, StorageClass, IngressClassParams)

### Requirement: Clean teardown
The test suite SHALL tear down all resources after testing, leaving no orphaned AWS resources.

#### Scenario: KRO instance deletion cascades
- **WHEN** the test deletes the KRO instance
- **THEN** ACK deletes all composed AWS resources (RDS, ECR, CloudFront, WAF, Route 53 records)

#### Scenario: Terraform destroy completes
- **WHEN** the test runs `terraform destroy` after KRO cleanup
- **THEN** all bootstrap resources (VPC, EKS cluster, IAM roles, state bucket contents) are removed

#### Scenario: No orphaned resources
- **WHEN** the test runs a post-teardown audit
- **THEN** no resources with the test's Project/Environment tags remain in the account (EC2, EBS, ENI, ALB, security groups)

### Requirement: Test isolation
The test suite SHALL use unique environment names and tags per test run to avoid conflicts with other deployments in the same account.

#### Scenario: Parallel test runs
- **WHEN** two test runs execute simultaneously
- **THEN** they use different VPCs, cluster names, and namespaces, with no resource collisions

### Requirement: Test execution modes
The test suite SHALL support both full (deploy + test + teardown) and test-only (against existing deployment) modes.

#### Scenario: Full mode
- **WHEN** the test runs in `full` mode
- **THEN** it deploys, validates, and tears down the entire stack

#### Scenario: Test-only mode
- **WHEN** the test runs in `test-only` mode against an existing endpoint
- **THEN** it validates the FHIR endpoint and tagging without deploying or destroying anything
