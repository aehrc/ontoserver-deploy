terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.25.0"
    }
  }


  backend "azurerm" {
    # Use backendconfig.tfvars to set this and call tarraform with -backend-config=backendconfig.tfvars
    #storage_account_name = "ontoexample_storage"
    #container_name       = "terraform_state"
    # Microsoft suggested backend setup for Azure backend storage
    key                  = "codelab.microsoft.tfstate"

    # Provide storage account  access key via ARM_ACCESS_KEY environment variable
    # access_key = "abcdefghijklmnopqrstuvwxyz0123456789..."
  }
}

provider "azurerm" {
  features {}
}
