# gop-multi-tenant-multi-cluster-example

IDP as a service: Deploy multiple tenants to dedicated clusters, managed centrally (Hub and spoke) using Argo CD app
sets and [GOP](https://github.com/cloudogu/gitops-playground).

## Running locally

### Create management cluster / tenant0

```bash
VERSION='cec82a7'
  
INSTANCE=0
bash <(curl -s "https://raw.githubusercontent.com/cloudogu/gitops-playground/$VERSION/scripts/init-cluster.sh") \
  --bind-ingress-port="808$INSTANCE" --cluster-name="c$INSTANCE" --bind-registry-port="3001$INSTANCE"
  
# Init mgmt cluster
docker run --rm -t --pull=always -u $(id -u) \
  -v ~/.config/k3d/kubeconfig-c0.yaml:/home/.kube/config \
    --net=host \
    ghcr.io/cloudogu/gitops-playground:$VERSION --yes --argocd --ingress-nginx --base-url=http://localhost
```

### Init tenant

```bash
# Push the tenant file right to Git
scripts/init-tenant.sh 1
# Or if you want to print the tenant file (e.g. for demos)
scripts/init-tenant.sh 2 false
```

### Create appsets

```bash
 curl -u admin:admin  'http://scmm.localhost:8080/scm/api/v2/edit/argocd/argocd/create/applications' -X POST \
  -F "file0=@cluster-resources/applications/tenants-appset.yaml;filename=file0" \
  -F 'commit={"commitMessage":"tenants-appset","branch":"main","names":{"file0":"/tenants-appset.yaml"}}'
````

Optional: Deploy an additional app from central argo to tenant clusters

```bash
curl -u admin:admin  'http://scmm.localhost:8080/scm/api/v2/edit/argocd/argocd/create/applications' -X POST \
-F "file0=@cluster-resources/applications/extra-app-appset.yaml;filename=file0" \
-F 'commit={"commitMessage":"extra-app-appset","branch":"main","names":{"file0":"/extra-app-appset.yaml"}}'
````

### Optional: Use Secret for config

When secret values, like passwords, have to be set in tenant config, a secret is the option of choice.

Here is an example of how to use one:

```bash
cat <<EOF > gop-config.yaml
apiVersion: v1
kind: Secret
metadata:
  name: gop-secret
  namespace: gop
type: Opaque
stringData:
  config.yaml: |
    application:
      username: "admin"
      password: "admin"
EOF

kubectl apply -f gop-config.yaml  --context k3d-c1
```

Add `configSecret: gop-secret` to `global-values.yaml` or `tenant-values.yaml`.
In a production env, these secrets could be created using ESO and vault.

### Delete tenant

#### Secret
```bash
kubectl get secret -n argocd --context k3d-c0 --selector argocd.argoproj.io/secret-type=cluster
# Pick one to delete
```

Or: Delete all

```bash
kubectl delete secret -n argocd --context k3d-c0 --selector argocd.argoproj.io/secret-type=cluster
```

#### Cluster

```bash
k3d cluster rm c1
```
