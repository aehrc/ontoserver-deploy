az network application-gateway ssl-cert create \
  --resource-group MC_example-ontos-resource-group_ontoserver-nzcts_australiaeast \
  --gateway-name aks-agw \
  -n mysslcert \
  --cert-file test-cert.pfx \
  --cert-password "test"
