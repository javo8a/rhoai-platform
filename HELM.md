# RHOAI 3.4 Helm Charts

Helm-based GitOps layout for deploying RHOAI 3.4 and Models-as-a-Service (MaaS), following the pattern from [openshift-setup](https://github.com/jharmison-redhat/openshift-setup).

This is the **platform GitOps repo** ([javo8a/rhoai-platform](https://github.com/javo8a/rhoai-platform)). Application-team values live in [javo8a/rhoai-workloads](https://github.com/javo8a/rhoai-workloads).

## Directory Layout

```
rhoai-platform/
├── charts/                         # Shared Helm charts (platform team)
├── clusters/                       # Per-cluster platform values
│   └── example.cluster.opentlc.com/
│       ├── cluster.yaml            # Global cluster name/domain/toolsImage
│       └── platform/values/{app}/  # Platform chart overrides
├── applications-templates/platform/  # Child Application templates (waves 1–6)
├── applications/clusters/{cluster}/  # Rendered Applications (generated)
│   ├── platform/
│   ├── bootstrap/
│   └── rhoai-maas-bootstrap.yaml
├── app-of-apps/                    # Root Application templates
├── argocd/projects/                # AppProject templates + rendered/
├── scripts/render-applications.sh  # Template renderer
└── HELM.md
```

## Ownership Split (Two Repos)

| Owner | Argo CD root app | Sync waves | Charts |
|-------|------------------|------------|--------|
| **Platform engineers** | `rhoai-platform` | 1–6 | `cert-manager`, `observability-operators`, `nvidia-gpu-enablement`, `leaderworkerset`, `rhcl`, `gateway-api`, `openshift-ai`, `maas-postgres`, `maas-controller` |
| **Application team** | `maas-workloads` | 7–8 | `llmisvc`, `maas-subscriptions` (in workloads repo) |

Platform delivers the MaaS **control plane** (operators, gateway, RHOAI, Postgres, Kuadrant policies). The application team delivers **workloads and catalog/access** (`LLMInferenceService`, `MaaSModelRef`, `MaaSAuthPolicy`, `MaaSSubscription`).

### Platform repo (this repo)

- Platform charts under `charts/` (waves 1–6)
- `clusters/{cluster}/cluster.yaml` and `clusters/{cluster}/platform/values/**`
- Platform Application templates, rendered `applications/`, AppProjects, bootstrap apps

### App-team repo ([rhoai-workloads](https://github.com/javo8a/rhoai-workloads))

```
rhoai-workloads/
├── charts/llmisvc/
├── charts/maas-subscriptions/
├── clusters/{cluster}/values/
└── applications/clusters/{cluster}/
    ├── maas-workloads.yaml
    └── workloads/
```

All workload Argo CD resources live in the workloads repo. Apply `maas-workloads.yaml` after platform sync is healthy.

**Model name contract:** keys in `llmisvc` `models:` must match names in `maas-subscriptions` `modelRefs`, `subscriptions`, and `authPolicies`.

## Install Order (Sync Waves)

| Wave | Chart | Owner | Description |
|------|-------|-------|-------------|
| 1 | `cert-manager` | Platform | cert-manager operator |
| 1 | `observability-operators` | Platform | Tempo, Cluster Observability, OpenTelemetry operators |
| 2 | `nvidia-gpu-enablement` | Platform | NFD + NVIDIA GPU operator and instances |
| 2 | `leaderworkerset` | Platform | Leader Worker Set operator and instance |
| 2 | `rhcl` | Platform | Red Hat Connectivity Link + Kuadrant |
| 3 | `gateway-api` | Platform | GatewayClass + maas-default-gateway |
| 4 | `openshift-ai` | Platform | RHOAI operator, DSC, dashboard, observability DSCI |
| 5 | `maas-postgres` | Platform | Optional in-cluster Postgres + `maas-db-config` for MaaS API |
| 6 | `maas-controller` | Platform | MaaS CRDs, RBAC, Kuadrant policies |
| 7 | `llmisvc` | App team | LLMInferenceService models |
| 8 | `maas-subscriptions` | App team | MaaSModelRef, MaaSAuthPolicy, MaaSSubscription |

## Quick Start

### 1. Configure platform values for your cluster

```bash
cp -r clusters/example.cluster.opentlc.com clusters/mycluster.mydomain.com
# Edit clusters/mycluster.mydomain.com/cluster.yaml:
#   global.cluster.name
#   global.cluster.baseDomain
#   global.toolsImage
```

### 2. Configure workloads values (app-team repo)

In [rhoai-workloads](https://github.com/javo8a/rhoai-workloads), add or edit:

- `clusters/mycluster.mydomain.com/values/llmisvc/values.yaml`
- `clusters/mycluster.mydomain.com/values/maas-subscriptions/values.yaml`

### 3. Render Argo CD Applications

Platform (this repo):

```bash
./scripts/render-applications.sh \
  --cluster mycluster.mydomain.com \
  --platform-repo https://github.com/javo8a/rhoai-platform.git \
  --platform-revision main \
  --workloads-repo https://github.com/javo8a/rhoai-workloads.git \
  --workloads-revision main \
  --argocd-namespace openshift-gitops
```

Workloads repo:

```bash
cd ../rhoai-workloads
./scripts/render-applications.sh \
  --cluster mycluster.mydomain.com \
  --workloads-repo https://github.com/javo8a/rhoai-workloads.git \
  --workloads-revision main \
  --argocd-namespace openshift-gitops
```

Commit platform rendered files under `applications/clusters/{cluster}/` and `argocd/projects/rendered/`. Commit workload rendered files in the workloads repo under `applications/clusters/{cluster}/`.

### 4. Bootstrap Argo CD (platform team)

1. Apply AppProjects from `argocd/projects/rendered/` to the GitOps namespace.
2. Create the bootstrap Application from `applications/clusters/{cluster}/rhoai-maas-bootstrap.yaml`.

The bootstrap app creates `rhoai-platform` (platform child apps, waves 1–6).

### 5. Bootstrap workloads (app team)

After platform sync is healthy, apply the root workload Application from the workloads repo:

```bash
oc apply -f applications/clusters/mycluster.mydomain.com/maas-workloads.yaml -n openshift-gitops
```

This creates `maas-workloads`, which syncs `llmisvc` (wave 7) and `maas-subscriptions` (wave 8).

### 6. App-team onboarding

After platform sync is healthy (see checklist below), the application team:

1. Pushes model/subscription values to their repo.
2. Syncs the `maas-workloads` Application (automated if enabled).
3. Validates models appear in the MaaS catalog and subscriptions grant access.

### Platform readiness checklist

Before relying on workload sync, confirm:

- [ ] `maas-default-gateway` is programmed in `openshift-ingress`
- [ ] DataScienceCluster and RHOAI dashboard are ready
- [ ] `maas-controller` Kuadrant policies exist
- [ ] `maas-db-config` secret exists (from in-cluster Postgres, external credentials, or day2 provisioning)
- [ ] GPU nodes are labeled if deploying GPU models (`nvidia.com/gpu.present=true`)

## Value Layering

### Platform charts

Charts merge values in this order (later overrides earlier):

1. `charts/{app}/values.yaml` — chart defaults
2. `clusters/{cluster}/cluster.yaml` — global cluster name/domain/toolsImage
3. `clusters/{cluster}/platform/values/{app}/values.yaml` — per-app overrides

The gateway hostname is templated from cluster globals:

```
maas.apps.{cluster.name}.{cluster.baseDomain}
```

### Disconnected clusters (optional)

For air-gapped or disconnected environments, set `disconnected.enabled: true` in `clusters/{cluster}/cluster.yaml` and update the registry/image fields for that cluster:

```yaml
disconnected:
  enabled: true
  wasmShimImage: registry.example.com/rhcl-1/wasm-shim-rhel9@sha256:...
  protectedRegistry: registry.example.com
  gatewayConfig:
    wasmInsecureRegistries: registry.example.com
    serviceType: ClusterIP  # lab only; omit on production clusters
```

This enables:

- **`rhcl`**: copies `pull-secret` to `wasm-plugin-pull-secret` and patches the operator subscription (`RELATED_IMAGE_WASMSHIM`, `PROTECTED_REGISTRY`) — bootstrap.sh step 11
- **`gateway-api`**: creates `default-gateway-config` with `WASM_INSECURE_REGISTRIES` for the gateway istio-proxy

Leave `disconnected.enabled: false` (default) on connected clusters such as OpenTLC sandboxes.

### MaaS PostgreSQL (optional per cluster)

MaaS API key storage requires a `maas-db-config` secret with `DB_CONNECTION_URL`. Configure this per cluster in `clusters/{cluster}/cluster.yaml`:

```yaml
maas:
  postgres:
    deploy:
      enabled: true   # sandbox/POC: deploy in-cluster PostgreSQL via maas-postgres chart
    dbConfig:
      secretName: maas-db-config
```

For **production** clusters with day2-managed PostgreSQL, disable the in-cluster deployment and point MaaS at your external database:

```yaml
maas:
  postgres:
    deploy:
      enabled: false
    dbConfig:
      secretName: maas-db-config
      # Option A: secret already provisioned outside this repo (recommended)
      existingSecret: maas-db-config
      # Option B: chart creates maas-db-config from a credentials secret + endpoints
      # credentialsSecret: maas-postgres-credentials
      # host: postgres.production.example.com
      # port: 5432
      # database: maas
      # user: maas
      # passwordKey: password
      # sslmode: require
```

When `deploy.enabled` is `true`, the chart deploys a single-replica PostgreSQL instance and a Job that builds `maas-db-config` from the bundled credentials. When `deploy.enabled` is `false` and `existingSecret` is set, the chart does not deploy PostgreSQL or run the Job — day2 operations own the secret. When `deploy.enabled` is `false` and `credentialsSecret` (or host/user) is set, the Job creates `maas-db-config` from the external connection details.

### Workload charts

1. `charts/{app}/values.yaml` — chart defaults (workloads repo)
2. `clusters/{cluster}/values/{app}/values.yaml` — per-cluster overrides (workloads repo)

## Argo CD GitOps

### AppProjects and RBAC

| AppProject | Team | `sourceRepos` | Destinations |
|------------|------|---------------|--------------|
| `rhoai-platform` | Platform | Platform repo only | Operator and system namespaces |
| `maas-workloads` | Application | Workloads repo only | `ai-models`, `models-as-a-service` |

Grant platform engineers `project/rhoai-platform` permissions. Grant application teams `project/maas-workloads` only — they can sync workloads without modifying operators or gateway configuration.

Templates: [`argocd/projects/rhoai-platform.yaml.tpl`](argocd/projects/rhoai-platform.yaml.tpl), [`argocd/projects/maas-workloads.yaml.tpl`](argocd/projects/maas-workloads.yaml.tpl).

### Platform child Application (single-source)

```yaml
spec:
  project: rhoai-platform
  source:
    path: charts/gateway-api
    repoURL: https://github.com/javo8a/rhoai-platform.git
    helm:
      valueFiles:
        - ../../clusters/example.cluster.opentlc.com/cluster.yaml
        - ../../clusters/example.cluster.opentlc.com/platform/values/gateway-api/values.yaml
```

### Workload child Application (single-source, workloads repo)

```yaml
spec:
  project: maas-workloads
  source:
    repoURL: https://github.com/javo8a/rhoai-workloads.git
    path: charts/llmisvc
    helm:
      valueFiles:
        - ../../clusters/example.cluster.opentlc.com/values/llmisvc/values.yaml
```

## Manual Helm Install (phased)

For clusters without Argo CD, install in wave order:

```bash
CLUSTER=clusters/example.cluster.opentlc.com
PLATFORM_CHARTS=charts
WORKLOADS=/path/to/rhoai-workloads
WORKLOAD_CHARTS=$WORKLOADS/charts
CLUSTER_VALUES=$WORKLOADS/clusters/example.cluster.opentlc.com

# Waves 1–6 (platform)
helm upgrade --install cert-manager $PLATFORM_CHARTS/cert-manager -n cert-manager-operator --create-namespace \
  -f $CLUSTER/cluster.yaml -f $CLUSTER/platform/values/cert-manager/values.yaml
# ... remaining platform charts ...

# Waves 7–8 (workloads — from rhoai-workloads repo)
helm upgrade --install llmisvc $WORKLOAD_CHARTS/llmisvc -n ai-models \
  -f $CLUSTER_VALUES/values/llmisvc/values.yaml
helm upgrade --install maas-subscriptions $WORKLOAD_CHARTS/maas-subscriptions -n models-as-a-service \
  -f $CLUSTER_VALUES/values/maas-subscriptions/values.yaml
```

## Bootstrap.sh Parity

All imperative steps from the upstream `bootstrap.sh` workflow are encoded in the Helm charts:

| bootstrap.sh step | Helm chart | Implementation |
|-------------------|------------|----------------|
| RHCL CSV `ISTIO_GATEWAY_CONTROLLER_NAMES` patch | `rhcl` | Job `patch-rhcl-csv` |
| Enable `kuadrant-console-plugin` | `rhcl` | Job `enable-console-plugin` |
| Gateway hostname patch | `gateway-api` | Templated from `cluster.yaml` |
| DataScienceCluster + Authorino NetworkPolicy | `openshift-ai` | Templates |
| Authorino service serving-cert annotation | `rhcl` | `service-authorino.yaml` (SSA) |
| Authorino TLS spec | `rhcl` | `authorino.yaml` |
| Restart kuadrant-operator-controller | `rhcl` | Job `restart-kuadrant-operator` |
| OdhDashboardConfig (MaaS dashboard flags) | `openshift-ai` | `odhdashboardconfig.yaml` |
| Postgres deployment (optional) | `maas-postgres` | `postgres.yaml` when `maas.postgres.deploy.enabled` |
| `maas-db-config` secret + maas-api restart | `maas-postgres` | Job `create-maas-db-config` (skipped when `existingSecret` is set) |
| MaaS Kuadrant policies | `maas-controller` | Policy templates |
| Simulated LLM models | `llmisvc` | Multi-model templates |
| MaaS subscriptions | `maas-subscriptions` | Subscription templates |
| Observability DSCI + cluster monitoring | `openshift-ai` | DSCInitialization + ConfigMap |
| `default-tenant` telemetry | `maas-subscriptions` | `tenant-telemetry.yaml` |
| Restart `rhods-dashboard` | `openshift-ai` | Job `restart-rhods-dashboard` |
| WASM shim disconnected workaround | `rhcl` | Job `apply-wasm-shim-workaround` (optional via `disconnected.enabled`) |
| Gateway `default-gateway-config` (WASM insecure registries) | `gateway-api` | ConfigMap `default-gateway-config` (optional via `disconnected.enabled`) |

Post-install Jobs use the cluster `toolsImage` (must include `oc` and `jq`) and run as Helm post-install/post-upgrade hooks (ArgoCD sync-wave ordered).

## Chart Sources

| Chart | Source |
|-------|--------|
| `install-operators`, `cert-manager`, `nvidia-gpu-enablement`, `leaderworkerset`, `rhcl`, `gateway-api`, `openshift-ai` | Adapted from [openshift-setup](https://github.com/jharmison-redhat/openshift-setup) |
| `llmisvc`, `maas-subscriptions` | In [rhoai-workloads](https://github.com/javo8a/rhoai-workloads) |
| `maas-postgres`, `maas-controller`, `observability-operators` | Created from upstream Kustomize manifests |

## Validation

Compare Helm output against Kustomize for parity:

```bash
# Gateway
helm template test charts/gateway-api \
  -f clusters/example.cluster.opentlc.com/cluster.yaml \
  -f clusters/example.cluster.opentlc.com/platform/values/gateway-api/values.yaml \
  | grep -A5 "kind: Gateway"

# kustomize build rhoai-3_4/overlays/03-gateway | grep -A5 "kind: Gateway"
```

Update chart dependencies after cloning:

```bash
for c in cert-manager nvidia-gpu-enablement rhcl leaderworkerset openshift-ai observability-operators; do
  (cd charts/$c && helm dependency update)
done
```
