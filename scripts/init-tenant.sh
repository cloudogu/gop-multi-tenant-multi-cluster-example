#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

TENANT=$1
PUSH_REPO=${2:-true}

BASEDIR=$(dirname $0)
ABSOLUTE_BASEDIR="$( cd $BASEDIR && pwd )"

function main() {
  createCluster

  echo adding Cluster secret to Argo CD argocd.localhost:8080
  addClusterSecret > /dev/null

  pushRepo
}

function createCluster() {
  echo Creating tenant cluster k3d-c$TENANT
  bash <(curl -s "https://raw.githubusercontent.com/cloudogu/gitops-playground/main/scripts/init-cluster.sh") \
   --bind-ingress-port="808$TENANT" --cluster-name="c$TENANT" --bind-registry-port="3001$TENANT" || true # Allow for recreate
}

set -x
function addClusterSecret() {
    # Change kubeconfig to docker internal URL, so an accessible URL is written to ArgoCD secret
    TMP_KUBECONFIG=$(mktemp)
    cp ~/.config/k3d/kubeconfig-c$TENANT.yaml $TMP_KUBECONFIG
    kubectl config set-cluster k3d-c$TENANT --kubeconfig=$TMP_KUBECONFIG \
     --server=https://$(docker inspect k3d-c${TENANT}-server-0| jq -r ".[0].NetworkSettings.Networks.\"k3d-c$TENANT\".IPAddress" ):6443

    # Allow network access from mgmt cluster to tenant cluster
    # k3d-c0-server-0 needs to be able to reach k3d-c1-serverlb under its IP address because only it is an allowed name in the TLS cert!
    docker network connect k3d-c$TENANT  k3d-c0-server-0 2>&1 >/dev/null || true

    # Add cluster secret for tenant to mgmt argo cd
    TMP_ARGOCONFIG=$(mktemp)
    yes | argocd login  argocd.localhost:8080   \
      --username admin --password admin \
       --config $TMP_ARGOCONFIG --grpc-web  || true > /dev/null

   yes | argocd cluster add k3d-c$TENANT --kubeconfig=$TMP_KUBECONFIG --config $TMP_ARGOCONFIG --grpc-web > /dev/null 2>&1 || true
   # For some reason we get pipe fails for these calls 🤷

    # WE can test if it works by running****
    # k run debug-$RANDOM   --restart='Never' --rm -ti --quiet  --image alpine
    # apk add kubectl
    # mkdir /root/.kube
    # Other shell: k cp .kube/config debug-13587:/root/.kube/config --context k3d-c1
    # kubectl get pod -A --context k3d-c2
}

function setScmmUrl() {
  # Make SCM in central cluster accessible from tenant cluster
  docker network connect k3d-c0  k3d-c$TENANT-server-0 >/dev/null 2>&1 || true

  MGMT_CONTAINER="http://$(docker inspect k3d-c0-server-0 | jq -r '.[0].NetworkSettings.Networks."k3d-c0".IPAddress'):$(kubectl get service scmm -n scm-manager --context k3d-c0 -o  jsonpath='{.spec.ports[*].nodePort}')/scm"

  # Replace only the first url line after scmm: section
  sed -i '/^scmm:/,/^[a-zA-Z]/ {
    /url:/ {
      s|url: "http://[^"]*"|url: "'"$MGMT_CONTAINER"'"|
      b
    }
  }' global-values.yaml
}

function pushRepo() {
    NAME=tenants NAMESPACE=argocd DESCRIPTION='' SCMM_HOST=scmm.localhost:8080/scm
    curl -sL -X POST -H "Content-Type: application/vnd.scmm-repository+json;v=2" \
        --data "{\"name\":\"${NAME}\",\"namespace\":\"${NAMESPACE}\",\"type\":\"git\",\"description\":\"${DESCRIPTION}\"}" \
        "http://admin:admin@${SCMM_HOST}/api/v2/repositories/?initialize=true" > /dev/null

    TMP_REPO=$(mktemp -d)
    git clone "http://admin:admin@$SCMM_HOST/repo/$NAMESPACE/$NAME" "${TMP_REPO}" > /dev/null 2>&1
    cp -r "${ABSOLUTE_BASEDIR}"/../tenants/* "${TMP_REPO}"

    (cd "${TMP_REPO}"

    setScmmUrl

    TENANT_IP=$(docker inspect k3d-c${TENANT}-server-0 | jq -r ".[0].NetworkSettings.Networks.\"k3d-c${TENANT}\".IPAddress")
    rm -rf tenant$TENANT
    sed -i "s|apiServerUrl: .*|apiServerUrl: https://${TENANT_IP}:6443|" tenantx/tenant-values.yaml
    #sed -i "s|baseHost: .*|baseHost: localhost:808$TENANT|" tenantx/tenant-values.yaml
    sed -i "s|tenantx|tenant$TENANT|" tenantx/tenant-values.yaml
    mv tenantx tenant$TENANT
    git config commit.gpgSign false
    git add tenant$TENANT global-values.yaml  > /dev/null 2>&1
    git commit -m "Add tenants folder" > /dev/null 2>&1 || true
    if [[ $PUSH_REPO == true ]]; then
      echo pushing tenant$TENANT to $SCMM_HOST/repo/$NAMESPACE/$NAME
      git push origin main > /dev/null 2>&1
    else
      echo "to create a new tenant push the following to $SCMM_HOST/repo/$NAMESPACE/$NAME"
      echo Path: tenant$TENANT
      echo FileName: tenant-values.yaml
      echo
      cat tenant$TENANT/tenant-values.yaml
    fi

      echo
      echo hint: Speed up app discovery by running the following
      echo "kubectl patch applicationset tenants -n argocd --context k3d-c0  --type='merge' -p '{\"metadata\": {\"annotations\": {\"argocd.argoproj.io/application-set-refresh\": \"true\"}}}'"
    )
    rm -rf "${TMP_REPO}"
}
main "$@"
