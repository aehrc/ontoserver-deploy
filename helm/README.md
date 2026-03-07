## Helm Charts
The provided [Helm](https://helm.sh/) charts help setting up and configure Ontoserver in a Kubernetes Cluster.
They provide deployment sources for the services and the Ingress Controllers and are parameterised to allow different kinds of setups, depending on what Ingress Controller is chosen.

Before you install the charts make sure the specific variables for your set up are set correctly in the chart's example `custom_values.yaml` that overwrites the default `values.yaml` file in the actual Helm chart sources.

### Ontoserver Helm chart
This Helm Chart installs Ontoserver on a Kubernetes Cluster with settings that can be customised by the externalised variables.
The default settings are located in [helm/ontoserver/ontoserver/values.yaml](helm/ontoserver/ontoserver/values.yaml) file. These settings are overwritten in [helm/ontoserver/ontoserver_values.yaml](helm/ontoserver/ontoserver_values.yaml) file when deploying the chart using the [helm/ontoserver/deploy.sh](helm/ontoserver/deploy.sh) deployment script.
By default the deployment script expects that you set `ONTOSERVER_NAMESPACE` environment variable is set properly and `DOCKER_USERNAME` and `DOCKER_PASSWORD` environment variables exported if you get the Ontoserver image from Quay.io. Please read the comments in the script how to set these variables and why are they part of the script.

Please note actual Ontoserver dot notated configuration settings should be under `ontoserver.config` in the values `.yaml` files. The available configuration items are listed in the documentation at [https://ontoserver.csiro.au/docs/6/config-all.html](https://ontoserver.csiro.au/docs/6/config-all.html)
E.g.: Ontoserver's `conformance.experimental: 'false'` should look like this:
```
ontoserver:
  config:
     conformance.experimental: 'false'
```
Also note for Ontoserver configuration items `true` and `false` values need to be enclosed in single quote `'` as these will be passed as environment variables to the docker image.


Here is a list of variables that are most likely to be customised for a new Ontoserver deployment.
| Setting      | Description |
| ----------- | ----------- |
| `ontoserver.image` | Name and version of the Ontoserver docker image. If Quay.io is used as a source docker repository this would be set to `quay.io/aehrc/ontoserver:<ctsa-version>`. For Quay.io images `repoSecret.enabled` has to be set to true and all settings under `repoSecret` need to be provided |
| `ontoserver.internalHostName` | Fully qualified domain name (FQDN) of the host name of the deployed Ontoserver running in Kubernetes.  This setting is used for the ingress controller. If Nginx ingress controller is used `nginx-ingress.controller.service.annotations.service.beta.kubernetes.io/azure-dns-label-name` can define this name . The ingress controller will create the following DNS name `<azure-dns-label-name>.<az-zone>.cloudapp.azure.com`. This might also be set to an Azure Application Gateway's Public IP address's DNS setting if AGIC is used as ingress controller. |
| `ontoserver.hostName` | FQDN where the Ontoserver deployment will be accessed from. This could be different from `internalHostName` for example if the deployment is using a customised domain name set in a CDN in front of the deployment. This setting is used for Ontoserver advertised urls.|
| `ontoserver.timeZone` | The time zone of the deployed server in tz format. [List of tz database time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones). |
| `ontoserver.persistence.*` | `ontoserver.persistence.enabled` set to `true` tells the deployment to set up disks for storing Ontoserver indexes and the internal database files. You can use the default PersistentVolumeClaims or provide an Azure FileShare or Azure Disk for the ontoserver files, or an Azure Disk for the database. If `ontoserver.database.external` is set to true `ontoserver.persistence.dbDiskName` and `ontoserver.persistence.dbDiskUri`, or the PersistentVolumeClaim are not used and only the Ontoserver files volume is set. |
| `ontoserver.resources.*` | This section sets the memory and the cpu Kubernetes limits for Ontoserver and for the database if an internal database running on Kubernetes. |
| `ontoserver.config.* ` | If any settings are provided under `ontoserver.config` variables it will be passed through to Ontoserver as an environment variable. So for example setting the following setup in the values files will set Ontoserver's `conformance.publisher` setting to `ontoserver.config.conformance.publisher: Example` |
| `ontoserver.database.external` | If set to `true` the deployment will not set up an internal database running in a Kubernetes pod but Ontoserver will use a database hosted on `ontoserver.database.host`. |
| `ontoserver.database.user` and `ontoserver.database.password` | Username and password to connect to an external database. This can be discarded when choosing the internal database running in a Kubernetes pod. |
| `ontoserver.waitForPreloadSuccess` | If set to `true` the deployment sets up a Kubernetes `readinessProbe` that checks that ontoserver preload is successfully finished. Otherwise the readinessProbe will only check that Ontoserver started successfully. |
| `ontoserver.customisation.mapname` | If this is set to anything but `false` the deployment mounts a custom stylesheet and a logo file for custom styling for CSIRO's Shrimp and Snapper apps. More on this at [Customisation for Snapper](#customisation) section. |
| `ontoserver.preload.bundle` | If this is set to anything but `false` the deployment mounts a [`preload.json`](ontoserver/ontoserver/preload/preload.json) file into the `/data` directory overwriting the default file in the container. The FHIR Bundle will be preloaded into Ontoserver at startup. Please note if you have preload feed set this bundle will not preload on startup unless you include `file:///data/preload.json` in your new feed. |
| `ontoserver.preload.feed` | If this is set to anything but `false` the deployment mounts a [`preload.xml`](ontoserver/ontoserver/preload/preload.xml) file into the `/data` directory overwriting the default file in the container. The content specified within the feed will be preloaded into Ontoserver at startup. |
| `ontoserver.tolerations.*` | By default this setting is `false` otherwise it can be used to pass Kubernetes tolerations settings to the pod by adding `-key` configuration item(s) under it. For example it can be used to schedule the Ontoserver pod on an Azure non-spot node for high availability if the K8s Cluster has mixed spot and non-spot nodes [More here](https://kubernetes.io/docs/concepts/scheduling-eviction/taint-and-toleration/) |
| `ontoserver.httpProxy` | Define a Global HTTP proxy for internet access.
| `ontoserver.httpsProxy` | Define a Global HTTPS proxy for internet access.
| `ontoserver.noProxy` | Define a list of domains to except from being proxied. eg. ".svc.cluster.local,.svc,.foo.com"
| `ontoserver.env.HTTP_PROXY_HOST` | Define an HTTP proxy for Ontoserver app internet access. (Ontoserver does not use system proxy ENV variables)
| `ontoserver.env.HTTP_PROXY_PORT` | Define an HTTP proxy port for Ontoserver app internet access. (Ontoserver does not use system proxy ENV variables)
| `ontoserver.env.HTTPS_PROXY_HOST` | Define an HTTPS proxy for Ontoserver app internet access. (Ontoserver does not use system proxy ENV variables)
| `ontoserver.env.HTTPS_PROXY_PORT` | Define an HTTPS proxy port for Ontoserver app internet access. (Ontoserver does not use system proxy ENV variables)
| `ingress.class` | This setting tells Kubernetes what kind of ingress class to use. The chart is set up to take `ontoserver-nginx`, the class name set under the `nginx-ingress.*` settings. It can also be set to `azure/application-gateway` or `alb` settings. |
| `ingress.sslRedirect` | If you want to host Ontoserver on http you need to set this config item to `false` otherwise all http requests are redirected to https. |
| `ingress.appgw.*` | These are settings for the Azure Application Gateway Ingress Controller. Here you can set `sslcertificate` - to use an Azure Application Gateway installed SSL certificate name - and `requesttimeout` to set request timeout in minutes. |
| `ingress.alb.*` | AWS ALB ingress controller settings. `loadBalancerGroup` sets the name the ingress controller group [belongs to](https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.2/guide/ingress/annotations/#ingressgroup). This is the `alb.ingress.kubernetes.io/group.name` ingress controller annotation. `certificateArn` is the Arn for the SSL certificate to be used for the endpoint. This is the `alb.ingress.kubernetes.io/certificate-arn` annotation. |
| `nginx-ingress.controller.service.annotations.service.beta.kubernetes.io/azure-dns-label-name` | Name to be used for the Azure generated DNS name when using `nginx` ingress controller. This will set the FQDN of Ontoserver to  `<name>.<az-zone>.cloudapp.azure.com`. |
| `nginx-ingress.controller.ingressClassResource.*` and `nginx-ingress.controller.ingressClass` | Unique name to be used for the instance of nginx ingress controller. Kubernetes 1.22.6+ requires Ingress class names to be unique accross all name spaces so the name `nginx` cannot be used for multiple Ingress resources. `nginx-ingress.controller.ingressClassResource.name` and `nginx-ingress.controller.ingressClass` should match and `nginx-ingress.controller.ingressClassResource.controllerValue` should have the name appended to `k8s.io/`. |
| `certmanager.enabled` | Set this to `true` if you have installed Kubernetes [Cert Manager](#cert-manager) and you want to use it to manage SSL certificates for the ingress controller. |
| `repoSecret.*` | These settings create a Docker credentials secret in Kubernetes to pass it for Docker repository authentication. It is used when the Ontoserver image is pulled from Quay.io. The `repoSecret.dockerconfigjson` setting need to be a base64 encoded Docker configuration file. A script is provided to help generate this configuration item [./quayio-secret-dockerconfigjson.sh](./quayio-secret-dockerconfigjson.sh) More on this here: https://kubernetes.io/docs/tasks/configure-pod-container/pull-image-private-registry/| 

#### Customisation for Snapper
Some custom styling can be passed to Ontoserver using the Helm chart that shows custom branding in CSIRO's Shrimp and Snapper apps. The apps look for `organisation.css` and `organisation_logo.png` files in the server's Fhir endpoint's `/.well-known/` location. [More about this here.](https://ontoserver.csiro.au/site/technical-documentation/snapper-documentation/customise-snapper-endpoint-branding/) 
If you want to use your own branding you need to set `ontoserver.customisation.mapname` other than `false` and replace [*ontoserver/ontoserver/customisation/organisation.css*](helm/ontoserver/ontoserver/customisation/organisation.css) and [*ontoserver/ontoserver/customisation/organisation_logo.png*](helm/ontoserver/ontoserver/customisation/organisation_logo.png) in the example.

### Cert-Manager
Cert manager is Cloud native certificate manager solution for Kubernetes and OpenShift. It simplifies TLS certificate management and automates certificate renewal for Letsencrypt certificates.

Scripts are included to install Cert-manager on a Kubernetes Cluster and a cert-issuer Helm chart to install the required `ClusterIssuer` resource. 
The example uses Nginx `http01` solver that requires an Nginx Ingress Controller to be installed in the cluster. Existing Nginx class names that are installed in the K8s cluster can be provided for example `ontoserver-example-nginx` but an included shell script can be used to install an nginx controller for this reason. [cert-manager/install-nginx-ingress-controller.sh](cert-manager/install-nginx-ingress-controller.sh)

Use [/cert-manager/install-cert-manager.sh](/cert-manager/install-cert-manager.sh) to install the cert-manager POD in the K8s cluster.
Then customise the cert issuer scripts and install it using [helm/cert-manager/install-cert-issuer.sh](helm/cert-manager/install-cert-issuer.sh)

> Make sure `certmanager.enabled` is set to `true` for the Ontoserver Helm charts to use this feature.
