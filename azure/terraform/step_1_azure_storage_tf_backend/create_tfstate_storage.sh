RESOURCE_GROUP_NAME=ontoexample_resourcegroup
STORAGE_ACCOUNT_NAME=ontoexample_storage
CONTAINER_NAME=terraform_state
LOCATION=australiaeast

# Create resource group
az group create \
   --name $RESOURCE_GROUP_NAME \
   --location $LOCATION

# Create storage account
az storage account create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name $STORAGE_ACCOUNT_NAME \
    --sku Standard_LRS \
    --encryption-services blob

# Enable blob versioning
az storage account blob-service-properties update \
    --resource-group $RESOURCE_GROUP_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --enable-versioning true \
    --enable-change-feed true

# Get storage account key
ACCOUNT_KEY=$(az storage account keys list \
                --resource-group $RESOURCE_GROUP_NAME \
                --account-name $STORAGE_ACCOUNT_NAME \
                --query [0].value -o tsv)

# Create blob container
az storage container create \
    --name $CONTAINER_NAME \
    --account-name $STORAGE_ACCOUNT_NAME \
    --account-key $ACCOUNT_KEY

