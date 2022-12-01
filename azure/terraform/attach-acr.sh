#!/bin/bash

##############################################################################
# Usage: ./attach-acr.sh <aks name> <resource group> <acr id>
# 
#  E,g: ./attach-acr.sh onto-exammple-k8s onto-example-group "/subscriptions/11111111-aaaa-bbbb-2222-cccccccccccc/resourceGroups/ontoserver-example/providers/Microsoft.ContainerRegistry/registries/ontoserverexample"
##############################################################################

az aks update -n $1 -g $2 --attach-acr $3