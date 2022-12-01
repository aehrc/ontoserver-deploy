#!/bin/bash

helm repo add nginx-stable https://helm.nginx.com/stable
helm repo update
helm install nginx-ingress-controller nginx-stable/nginx-ingress -n nginx-ingress-controller --create-namespace