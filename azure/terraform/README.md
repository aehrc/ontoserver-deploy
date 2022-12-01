# Terraform scripts

## step_1_azure_storage_tf_backend
The shell script in this directory sets up an Azure Blob Storage resource to hold the Terraform state files for the main infrastructure.
It also creates the Resource Group for the infrastructure Terraform scripts. To run the script make sure you Azure CLI is installed and you are logged into the Azure tenancy. The run
```
./create_tfstate_storage.sh
```

## step_2_infrastructure
The terraform scripts in this directory create the infrastucture in Azure Cloud Services. The scripts require the storage environment to be set up in the previous step.
- [main.tf](step_2_infrastructure/main.tf) - Main terraform script that defines the providers and the backend
- [acr.tf](step_2_infrastructure/acr.tf) - Script to create Azure Container Registry that holds Ontoserver images
- [aks.tf](step_2_infrastructure/aks.tf) - This script creates the Azure Kubernetes Service that runs Ontoserver
- [backendconfig.tfvars](step_2_infrastructure/backendconfig.tfvars) - Storage configuration for Terraform backend
- [db.tf](step_2_infrastructure/db.tf) - Azure Database for PostgreSQL for the Ontoserver backend
- [disk.tf](step_2_infrastructure/disk.tf) - Managed disks for Ontoserver indexes and Ontocloak files
- [network.tf](step_2_infrastructure/network.tf) - AKS Virtual Network resource
- [resource_group.tf](step_2_infrastructure/resource_group.tf) - Dataset defining the Resource Group created in the previous setup step
- [terraform.tfvars](step_2_infrastructure/terraform.tfvars) - Terraform variable overrides
- [variables.tf](step_2_infrastructure/variables.tf)- Required variables for the scripts, including secrets that should be set as environment variables and not stored in version control
- [outputs.tf](step_2_infrastructure/outputs.tf) - Defined outputs for Helm chart and for reference

## step_3_CDN
Optional caching solution using Azure CDN Akamai profile. It requires an Ontoserver endpoint host name as an input for Origin Host.
- [main.tf](step_2_infrastructure/main.tf) - Main terraform script that defines the providers and the backend
- [cache.tf](step_3_CDN/cache.tf) - This script creates the Azure CDN profile
- [resource_group.tf](step_3_CDN/resource_group.tf) - Dataset defining the Resource Group created in step_1
- [variables.tf](step_3_CDN/variables.tf)- Required variables for the scripts, including secrets that should be set as environment variables and not stored in version control
- [outputs.tf](step_3_CDN/outputs.tf) - Defined outputs for reference


Terraform is required to be installed to run these scripts. 
The access key to the Storage account created in the first step needs to be provided in the `ARM_ACCESS_KEY` env variable and `az login` need to be executed before `terraform init --backend-config=backendconfig.tfvars`


First run this command to set up the Terraform environment
```
terraform init --backend-config=backendconfig.tfvars
```
Then check that everything is working by issuing
```
terraform plan
```
If everything is fine and there are no issues reported, the scripts can be executed with
```
terraform apply
```

## Attach ACR
The Azure Container Registry created by the Terraform scripts is not attached to the AKS cluster by default. Please use the [attach-acr.sh](attach-acr.sh) script to do this task.