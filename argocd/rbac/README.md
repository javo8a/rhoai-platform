# Argo CD RBAC (OpenShift GitOps)

## Application controller cluster permissions

OpenShift GitOps ships a restricted ClusterRole for the application controller.
RHOAI platform charts need broader create/update permissions (ServiceAccounts,
Deployments, Gateways, etc.). Apply once per cluster **before** bootstrapping:

```bash
oc apply -f argocd/rbac/gitops-application-controller-clusteradmin.yaml
```

## Example Argo CD user/group RBAC

Apply after AppProjects. Adjust group names to match your IdP.
#
# Platform engineers — full access to rhoai-platform project:
#
#   g, platform-admins, role:admin
#   p, role:platform-admin, projects, get, rhoai-platform, allow
#   p, role:platform-admin, applications, *, rhoai-platform/*, allow
#   g, platform-admins, role:platform-admin
#
# Application team — sync workloads only:
#
#   p, role:workloads-admin, projects, get, maas-workloads, allow
#   p, role:workloads-admin, applications, get, maas-workloads/*, allow
#   p, role:workloads-admin, applications, sync, maas-workloads/*, allow
#   p, role:workloads-admin, applications, update, maas-workloads/*, allow
#   g, app-team, role:workloads-admin
#
# Add these policies to the Argo CD instance spec:
#   spec.rbac.policy or argocd-rbac-cm ConfigMap (OpenShift GitOps).
