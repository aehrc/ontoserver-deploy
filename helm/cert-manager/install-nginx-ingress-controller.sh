#!/bin/bash

helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
helm upgrade --install nginx-ingress-controller nginx-stable/nginx-ingress -n nginx-ingress-controller --create-namespace \
  --set controller.tolerations[0].key="kubernetes.azure.com/scalesetpriority" \
  --set controller.tolerations[0].operator="Equal" \
  --set controller.tolerations[0].value="spot" \
  --set controller.tolerations[0].effect="NoSchedule"
