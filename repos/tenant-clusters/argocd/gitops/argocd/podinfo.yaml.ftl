apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: podinfo
  namespace: podinfo
spec:
  destination:
    server: https://kubernetes.default.svc
    namespace: podinfo
  project: tenant
  sources:
    - repoURL: ghcr.io/stefanprodan/charts
      targetRevision: 6.9.2
      chart: podinfo
      helm:
        valuesObject:
          ui:
            message: Welcome to Tenant ${config.application.namePrefix?remove_ending("-")}
          ingress:
            enabled: true
            hosts:
              - host: podinfo.${config.application.namePrefix?remove_ending("-")}.localhost
                paths:
                  - path: /
                    pathType: ImplementationSpecific
  syncPolicy:
    automated:
      prune: true
      selfHeal: true