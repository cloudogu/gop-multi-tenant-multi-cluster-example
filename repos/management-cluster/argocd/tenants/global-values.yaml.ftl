# Used in appset only, defined per tenant
# apiServerUrl: https://x.x.x.x:6443

# Helm values
image:
  tag: "0.12.1"

# GOP config 
config:
  application:
    baseUrl: "http://localhost"
  content:
    repos:
      - url: https://github.com/cloudogu/gop-multi-tenant-multi-cluster-example
        path: repos/tenant-clusters
        templating: true
        type: FOLDER_BASED
        overwriteMode: UPGRADE
    variables:
      scmmUrl: "${config.content.variables.scmmUrl}"
    namespaces:
      - podinfo
  features:
    argocd:
      active: true
    ingressNginx:
      active: true
    #monitoring:
    #  active: true

  # Make tenants use central SCMM instance. Remove to deploy separate instances into tenant
  scmm:
    url: "${config.content.variables.scmmUrl}"
    username: "admin"
    password: "admin"
    skipPlugins: true # Faster installation for demo purposes

# Central management of all tenants (Hub and spoke) - not implemented for multi-cluster, yet
#  multiTenant:
#    useDedicatedInstance: true
#    centralScmUrl: "${config.content.variables.scmmUrl}"
#    username: admin
#   password: admin
  
#  registry:
#    url: "localhost:30000"

# Uncomment to make tenants use central jenkins - not implemented, yet
#  jenkins:
#    url: "http://172.18.0.2:35888"
#    username: "admin"
#    password: "admin"
