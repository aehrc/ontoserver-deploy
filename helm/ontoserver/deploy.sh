#!/bin/bash

helm dependency update ./ontoserver

ONTOSERVER_NAMESPACE=ontoserver-example
REPOSECRET_ENABLED=true

# Using quay.io image
# By default the Helm chart is using the official Ontoserver docker image from Quay.io
# Either provide DOCKERCONFIGJSON environment variable or make sure
# username and password is provided either by hard coding it into the quayio-secret-dockerconfigjson.sh file
# or by exporting these two environment variables:
# export DOCKER_USERNAME=<quay.io username>
# export DOCKER_PASSWORD=<quay.io password>
if [ "${DOCKERCONFIGJSON}" == ""  -a "${REPOSECRET_ENABLED}" == "true" ]; then
  . ./quayio-secret-dockerconfigjson.sh
fi

# Quay io
helm upgrade --dry-run --install --namespace $ONTOSERVER_NAMESPACE --values custom_values.yaml \
    --set repoSecret.enabled=$REPOSECRET_ENABLED,repoSecret.name="quayioreposecret",repoSecret.dockerconfigjson="$DOCKERCONFIGJSON" \
    --wait --timeout 30m --create-namespace $ONTOSERVER_NAMESPACE ./ontoserver
