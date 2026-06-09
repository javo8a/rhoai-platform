---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: cert-manager
  annotations:
    argocd.argoproj.io/sync-wave: "1"
spec:
  project: rhoai-platform
  destination:
    name: in-cluster
    namespace: cert-manager-operator
  source:
    path: charts/cert-manager
    repoURL: ${ARGO_GIT_URL}
    targetRevision: ${ARGO_GIT_REVISION}
    helm:
      valueFiles:
        - ../../clusters/${ARGO_CLUSTER_DIR}/cluster.yaml
        - ../../clusters/${ARGO_CLUSTER_DIR}/platform/values/cert-manager/values.yaml
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
