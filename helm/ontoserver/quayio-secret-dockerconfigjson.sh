#!/bin/bash

# Provide username and password in a secure way setting and exporting these two environment variables:
# export DOCKER_USERNAME=<quay.io username>
# export DOCKER_PASSWORD=<quay.io password>

NAME="quayio-seccret"
SERVER="quay.io"
DOCKER_USERNAME=${DOCKER_USERNAME:-"user"}
DOCKER_PASSWORD=${DOCKER_PASSWORD:-"password"}
NAMESPACE="default"

QUAYIOSECRET=$(kubectl create secret docker-registry $NAME \
    --dry-run=client \
    --docker-server=$SERVER \
    --docker-username=$DOCKER_USERNAME \
    --docker-password=$DOCKER_PASSWORD \
    --namespace=$NAMESPACE \
    -o yaml)

DOCKERCONFIGJSON=$(echo "$QUAYIOSECRET" | grep "\.dockerconfigjson" | sed 's/^[ \t\.dockerconfigjson]*//;s/: //;s/$//')
