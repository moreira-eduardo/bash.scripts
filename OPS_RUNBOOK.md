# Ops Runbook — kubectl / az / flux / terraform / helm / istio (Generic)

A guide for operating Kubernetes/Azure/GitOps stacks.
Command frequencies below were derived from real operator history (extracted and analyzed from more than 10k entries from my terminal); replace
placeholders (`<ns>`, `<cluster>`, `<rg>`, `<name>`, `<sub>`) with values
from the environment.

---

## 1. `kubectl` — Day-to-day cluster operations

### Top commands by usage

| Count | Command pattern |
|------:|-----------------|
| 1667  | `kubectl get pods` |
|  520  | `kubectl describe pod` |
|  210  | `kubectl get secret` |
|  206  | `kubectl top nodes` |
|  200  | `kubectl apply -f` |
|  134  | `kubectl get all` |
|   98  | `kubectl rollout restart` |
|   89  | `kubectl delete pod` |
|   75  | `kubectl get nodes` |
|   65  | `kubectl get endpoints` |
|   54  | `kubectl delete deployment` |
|   53  | `kubectl get azurekeyvaultsecret` |
|   44  | `kubectl get svc` / `pvc` |
|   42  | `kubectl create secret` |
|   35  | `kubectl get pdb` |

### 1.1 Inspecting workloads

The first thing after fetching cluster credentials is to sanity-check pods.
On multi-tenant clusters **always pass `-n <ns>`**.

```bash
kubectl get pods -n <ns>
kubectl get pods -n <ns> -o wide          # add node + IP columns
kubectl get pods -n <ns> --watch          # follow rollouts live
kubectl get all  -n <ns>                  # everything in one shot
```

**Use case:** "Service X is down" → `get pods` first. `CrashLoopBackOff`,
`ImagePullBackOff`, or `Pending` already explains 80% of incidents.

### 1.2 Why a pod is unhealthy: `describe` + `logs`

```bash
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --tail=200
kubectl logs <pod> -n <ns> -c <container> --previous   # prior crash
kubectl logs -f deploy/<deployment> -n <ns>            # follow a Deployment
```

`describe` shows scheduling events, probe failures, OOMKills, volume mount
errors and image pull errors. **Always read the `Events:` section first.**

### 1.3 Rolling out changes

When a cluster is GitOps-managed you rarely `kubectl apply` directly, **but
restarting deployments is the most common safe recovery action**:

```bash
kubectl rollout restart deployment/<name> -n <ns>
kubectl rollout status   deployment/<name> -n <ns>
kubectl rollout history  deployment/<name> -n <ns>
kubectl rollout undo     deployment/<name> -n <ns>
```

Use cases:
- Picking up a new image after a registry-side change.
- Re-mounting a refreshed Secret/ConfigMap (Kubernetes does **not** auto-roll).
- Clearing wedged pods after a node issue.

For StatefulSets:
```bash
kubectl rollout restart statefulset/<name> -n <ns>
```

### 1.4 Secrets & Azure Key Vault to Kubernetes (akv2k8s)

When using the `azurekeyvaultsecret` CRD, inspect both the CRD and the
resulting `Secret`:

```bash
kubectl get azurekeyvaultsecret -n <ns>
kubectl get azurekeyvaultsecret <name> -n <ns> -o yaml
kubectl get secret <name> -n <ns> -o jsonpath='{.data.<key>}' | base64 -d
kubectl get secrets --all-namespaces | grep <pattern>
```

Manual one-off Secret (bootstrapping or debugging):
```bash
kubectl create secret generic my-secret \
  --from-literal=token=xxxx \
  -n <ns> --dry-run=client -o yaml | kubectl apply -f -
```

### 1.5 Node pressure & capacity

```bash
kubectl top nodes
kubectl top pods -n <ns> --sort-by=memory
kubectl describe node <node>             # taints, allocatable, conditions
kubectl get nodes -o wide --show-labels
```

### 1.6 Draining a node (maintenance / SKU upgrade)

```bash
kubectl cordon <node>                    # mark unschedulable
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --force
# ... do the work / let the cloud replace the node ...
kubectl uncordon <node>
```

### 1.7 PodDisruptionBudgets — the silent drain blocker

If `drain` hangs, a PDB is usually responsible:

```bash
kubectl get pdb -A
kubectl patch pdb <name> -n <ns> -p '{"spec":{"minAvailable":0}}'   # temporary
kubectl delete pdb <name> -n <ns>                                   # nuclear
```
Re-apply the PDB from Git afterwards.

### 1.8 Networking debug

```bash
kubectl get svc -n <ns>
kubectl get endpoints <svc> -n <ns>             # Service must back actual pods
kubectl get virtualservice <name> -n <ns> -o yaml   # Istio routing
kubectl get gateway -n istio-system
```
Empty `Endpoints` ⇒ Service selector doesn't match any Pod labels.

### 1.9 Storage

```bash
kubectl get pvc -n <ns>
kubectl describe pvc <name> -n <ns>
kubectl delete pvc <name> -n <ns>          # only after deleting workload
# Removing a PV finalizer when stuck Terminating:
kubectl patch pv <pv> -p '{"metadata":{"finalizers":null}}'
```

---

## 2. `az` — Azure control plane

### Top commands by usage

| Rank | Command |
|-----:|---------|
| 1    | `az aks get-credentials` |
| 2    | `az aks nodepool …` |
| 3    | `az login` |
| 4    | `az pipelines list` |
| 5    | `az keyvault secret …` |
| 6    | `az ad sp …` |
| 7    | `az account set` |
| 8    | `az network lb …` |

### 2.1 Login & subscription context

```bash
az login                                                           # device flow
az login --scope https://management.core.windows.net//.default     # token only
az login --identity                                                # on a VM/AKS
az account list -o table
az account set --subscription <sub-id>
az account show
```

### 2.2 AKS credentials

```bash
az aks get-credentials \
  --resource-group <rg> --name <cluster> \
  --file ./kubeconfig                          # don't pollute ~/.kube
az aks get-credentials \
  --resource-group <rg> --name <cluster> --overwrite-existing
```
Tip: `--file ./kubeconfig` keeps cluster contexts isolated per shell — pair
with `export KUBECONFIG=$PWD/kubeconfig`.

### 2.3 Node pools (scale, upgrade, add)

```bash
# List
az aks nodepool list --cluster-name <cluster> --resource-group <rg> -o table

# Add a new SKU pool
az aks nodepool add \
  --resource-group <rg> --cluster-name <cluster> \
  --name <pool> --node-count 1 --node-vm-size <SKU> \
  --labels workload=<label> --node-taints <key>=<val>:NoSchedule

# Scale
az aks nodepool scale --cluster-name <cluster> --resource-group <rg> \
  --name <pool> --node-count <n>

# Upgrade in place
az aks nodepool upgrade --cluster-name <cluster> --resource-group <rg> \
  --name <pool> --kubernetes-version <x.y.z>
```

### 2.4 Capacity / quota checks before scaling

```bash
az vm list-usage    --location <region> -o table | grep <SKU-family>
az vm list-skus     --location <region> --resource-type virtualMachines -o table
az quota list --scope "/subscriptions/<sub>/providers/Microsoft.Compute/locations/<region>"
az quota update ...   # only if you have entitlement; usually a support ticket
```

### 2.5 Key Vault — set/read secrets used by akv2k8s

```bash
az keyvault secret set  --vault-name <vault> --name <name> --value "$VALUE"
az keyvault secret show --vault-name <vault> --name <name> --query value -o tsv
az keyvault secret list --vault-name <vault> -o table
```

### 2.6 Azure Pipelines (CI triggers / inspection)

```bash
az pipelines list --organization "https://dev.azure.com/<org>" \
  --project "<project>" \
  --query "[].{Name:name,Id:id}" -o table
az pipelines run --id <id> --branch main
```

### 2.7 Networking (LB, DNS)

```bash
az network lb list --resource-group <mc-rg> \
  --query "[].{name:name,id:id}" -o table
az network lb frontend-ip list --lb-name <lb> --resource-group <mc-rg>

az network dns zone list -o table
az network private-dns record-set a update \
  --zone-name <zone> --resource-group <rg> \
  --name <record> --set aRecords[0].ipv4Address=<ip>
```

### 2.8 Service principals & OIDC (workload identity)

```bash
az ad sp create-for-rbac --name <name> --role Contributor \
  --scopes /subscriptions/<sub>/resourceGroups/<rg>
az aks show --name <cluster> --resource-group <rg> \
  --query "oidcIssuerProfile.issuerUrl" -o tsv
```

---

## 3. `flux` — GitOps reconciliation

When a Git repo is the source of truth, `Kustomization`/`HelmRelease`
resources point at folders/charts and Flux applies them.

### Top commands by usage

| Rank | Command |
|-----:|---------|
| 1    | `flux reconcile source git flux-system -n flux-system` |
| 2    | `flux get kustomizations` |
| 3    | `flux reconcile kustomization …` |

### 3.1 The "I just pushed to main, apply it now" flow

```bash
# 1) Pull the new Git revision into the cluster
flux reconcile source git flux-system -n flux-system

# 2) Re-apply all Kustomizations that depend on it
flux reconcile kustomization flux-system --with-source

# 3) Reconcile a specific stack (faster, smaller blast radius)
flux reconcile kustomization <name> --with-source
flux reconcile kustomization <name> --namespace flux-system --force
```

`--with-source` forces Flux to refresh the upstream source (Git or Helm repo)
first, then re-apply. Use `--force` to override "no change detected" caching.

### 3.2 Status & inventory

```bash
flux get kustomizations -A          # is everything Ready=True?
flux get sources git -A
flux get helmreleases -A
flux get image policy -A            # image automation
flux get imageupdateautomation -A
flux tree kustomization <name>      # what objects does it own?
flux events -A | tail -50
```

### 3.3 HelmReleases

```bash
flux reconcile source helm <repo> -n flux-system
flux reconcile helmrelease <name> -n <ns> --with-source
flux suspend  helmrelease  <name> -n <ns>     # pause GitOps to hand-edit
flux resume   helmrelease  <name> -n <ns>
```

### 3.4 Suspend/resume — the safety switch

When you need a *temporary* manual change without Flux reverting it:

```bash
flux suspend kustomization <name> -n flux-system
# ... kubectl edit ... debug ...
flux resume  kustomization <name> -n flux-system
```
**Always resume before leaving for the day.**

### 3.5 Bootstrap (first time only)

```bash
flux install --namespace flux-system
flux bootstrap github --owner <org> --repository <repo> \
  --branch main --path clusters/<env>
```

---

## 4. `terraform` — Infrastructure provisioning

### Top commands by usage

| Rank | Command |
|-----:|---------|
| 1    | `terraform plan` |
| 2    | `terraform init` |
| 3    | `terraform import` |
| 4    | `terraform apply` |
| 5    | `terraform state rm` |
| 6    | `terraform state list` |
| 7    | `terraform init -upgrade` |
| 8    | `terraform state mv` / `apply -target` |

### 4.1 Standard cycle

```bash
terraform init                         # first run, or after backend changes
terraform init -upgrade                # bump providers/modules
terraform plan -out tf.plan
terraform apply tf.plan
terraform plan -lock=false             # CI/parallel plans only — never apply with this
terraform plan -parallelism=20         # speed up cloud refresh
```

### 4.2 Targeted apply — surgical changes

```bash
terraform apply -target=module.<m>.<resource_type>.<name>
```
Use sparingly. It bypasses dependency ordering. **Follow with a full
`plan`/`apply` to converge.**

### 4.3 Importing existing cloud resources

When something was created via the portal/CLI and needs to fall under
Terraform control:

```bash
terraform import <address> <cloud-id>

# Example shapes
terraform import module.<m>.azurerm_<type>.<name> \
  /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.<svc>/<...>/<id>
```

For modules using `for_each` / `count`, **single-quote** the address:

```bash
terraform import 'module.<m>.<resource>.<name>[0]' <cloud-id>
terraform import 'module.<m>.<resource>.<name>["key"]' <cloud-id>
```

After import, **always run `terraform plan`** — diffs reveal arguments you
need to add to your `.tf` files to match reality.

### 4.4 State surgery

```bash
terraform state list
terraform state show <address>
terraform state mv  <old-address> <new-address>     # rename/move
terraform state rm  <address>                       # forget (no destroy)
terraform state pull > backup.tfstate               # always backup first!
```
Rule of thumb: **`state rm` before deleting code** for resources you want to
keep in the cloud but stop managing. **Never** `state rm` something you also
want gone — use `terraform destroy -target=` instead.

### 4.5 Provider/version checks

```bash
terraform --version
terraform providers
```

---

## 5. `istioctl` & Istio resources — Service mesh

In a mesh-enabled cluster, traffic routing, mTLS and authorization live in
Istio CRDs (`VirtualService`, `DestinationRule`, `Gateway`,
`AuthorizationPolicy`, `PeerAuthentication`). Most day-to-day inspection is
done through `kubectl` against those CRDs; `istioctl` is reserved for mesh
install, validation and deep proxy debugging.

### Top commands by usage

| Rank | Command |
|-----:|---------|
| 1    | `kubectl get virtualservice -A` |
| 2    | `kubectl describe virtualservice <name> -n <ns>` |
| 3    | `kubectl get destinationrule -A` |
| 4    | `kubectl get gateway -n istio-system` |
| 5    | `kubectl get authorizationpolicy -A` |
| 6    | `istioctl analyze <file-or-ns>` |
| 7    | `istioctl proxy-status` |
| 8    | `istioctl proxy-config <cluster\|listener\|route\|endpoint> <pod>` |

### 5.1 Inspecting routing (VirtualService / DestinationRule / Gateway)

```bash
kubectl get virtualservice -A
kubectl get virtualservice -n <ns> -o wide
kubectl describe virtualservice <name> -n <ns>
kubectl get virtualservice <name> -n <ns> -o yaml

kubectl get destinationrule -A
kubectl describe destinationrule <name> -n <ns>

kubectl get gateway -n istio-system
kubectl describe gateway <name> -n istio-system
```

**Use case:** A request returns `404` or hits the wrong cluster. Check the
`VirtualService` `hosts:` and `http.route.destination.host` first — typos
like `<svc>.ea.svc.cluster.local` vs. `<svc>.ga.svc.cluster.local` are the
classic culprit.

### 5.2 Authorization & mTLS

```bash
kubectl get authorizationpolicy -A
kubectl describe authorizationpolicy <name> -n istio-system
kubectl get peerauthentication -A
kubectl describe peerauthentication <name> -n <ns>
```
An `AuthorizationPolicy` with `action: DENY` matching everything in a
namespace will silently 403 all traffic — always check `-A` after a security
change.

### 5.3 Validating manifests with `istioctl analyze`

```bash
istioctl analyze <file.yaml>                    # validate a single manifest
istioctl analyze -n <ns>                        # validate live namespace
istioctl analyze --all-namespaces
istioctl validate -f <file.yaml>                # CRD schema validation only
```
Run `analyze` in CI / pre-commit on every PR that touches `VirtualService`,
`DestinationRule`, or `Gateway`.

### 5.4 Proxy / Envoy debugging

```bash
istioctl proxy-status                            # are all sidecars in sync with the control plane?
istioctl proxy-config cluster   <pod> -n <ns>    # upstream clusters Envoy knows about
istioctl proxy-config listener  <pod> -n <ns>    # bound listeners
istioctl proxy-config route     <pod> -n <ns>    # HTTP route table
istioctl proxy-config endpoint  <pod> -n <ns>    # resolved endpoints + health
istioctl proxy-config secret    <pod> -n <ns>    # mTLS material
```

**Use case:** "VirtualService is applied but traffic still goes the old
way." Run `istioctl proxy-status` — if a pod is `STALE`, the sidecar hasn't
received the new config from `istiod`. Restart the pod or investigate
`istiod`.

### 5.5 Debug an HTTP path end-to-end

```bash
# 1) Confirm the VS exists and matches the requested host
kubectl get virtualservice -A | grep <host>
kubectl describe virtualservice <name> -n <ns>

# 2) Confirm Envoy sees the route
istioctl proxy-config route <ingress-gateway-pod> -n istio-system \
  --name http.80 -o json | jq '.[].virtualHosts[] | select(.domains[]|test("<host>"))'

# 3) Confirm the upstream has endpoints
istioctl proxy-config endpoint <ingress-gateway-pod> -n istio-system \
  --cluster "outbound|<port>||<svc>.<ns>.svc.cluster.local"

# 4) Tail Envoy access logs
kubectl logs <ingress-gateway-pod> -n istio-system -c istio-proxy --tail=100
```

### 5.6 Sidecar injection

```bash
kubectl label namespace <ns> istio-injection=enabled --overwrite
kubectl get namespace -L istio-injection
# Force-inject a one-off manifest:
istioctl kube-inject -f deploy.yaml | kubectl apply -f -
```
A pod missing the `istio-proxy` container almost always means the namespace
label is not set, or the pod has `sidecar.istio.io/inject: "false"`.

### 5.7 Mesh install / upgrade (rare, usually GitOps-managed)

```bash
istioctl version
istioctl install --set profile=default                  # interactive confirm
istioctl install -f istio-operator.yaml -y
istioctl upgrade  -f istio-operator.yaml
istioctl manifest generate -f istio-operator.yaml > istio.yaml   # for review/PR
```

---

## 6. `helm` — Chart installs (mostly bootstrap)

In a GitOps setup Helm is rarely invoked directly — Flux's `HelmRelease`
takes over. The exceptions are bootstrap installs of cluster-wide
controllers.

### Top commands by usage

| Rank | Command |
|-----:|---------|
| 1    | `helm upgrade --install` |
| 2    | `helm repo add` |
| 3    | `helm list -A` |

### 6.1 Repo setup

```bash
helm repo add <name> <url>
helm repo update
```

### 6.2 Bootstrap installs

```bash
helm upgrade --install <release> <repo>/<chart> \
  --namespace <ns> --create-namespace \
  -f values.yaml --set <key>=<value>
```

### 6.3 Inspection

```bash
helm list -A
helm get values   <release> -n <ns>
helm get manifest <release> -n <ns>
helm history      <release> -n <ns>
helm rollback     <release> <revision> -n <ns>
```

### 6.4 Local chart workflow

```bash
helm lint     ./charts/<chart>
helm template ./charts/<chart> -f values.yaml | less
helm upgrade --install <release> ./charts/<chart> -n <ns> --dry-run
```
Prefer `helm template | kubectl diff -f -` for change previews when Flux
isn't owning the release.

---

## 7. End-to-end: common scenarios

### 7.1 "Service X is broken"

```bash
az aks get-credentials -g <rg> -n <cluster> --file ./kubeconfig
export KUBECONFIG=$PWD/kubeconfig

kubectl get pods -n <ns> | grep <svc>
kubectl describe pod <pod> -n <ns>
kubectl logs <pod> -n <ns> --tail=200 --previous
kubectl rollout restart deployment/<svc> -n <ns>
```

### 7.2 "I merged a manifest change to main"

```bash
flux reconcile source git flux-system -n flux-system
flux reconcile kustomization <stack> --with-source
flux get kustomizations -A | grep -v True   # anything not Ready?
```

### 7.3 "Need to scale for a load test"

```bash
az aks nodepool scale --cluster-name <cluster> --resource-group <rg> \
  --name <pool> --node-count <n>
kubectl top nodes
kubectl scale deployment <svc> -n <ns> --replicas=<n>
```

### 7.4 "Drain a node for upgrade"

```bash
kubectl cordon <node>
kubectl get pdb -A                             # check first
kubectl drain <node> --ignore-daemonsets --delete-emptydir-data
kubectl uncordon <node>                        # if it comes back
```

### 7.5 "Adopt a portal-created cloud resource"

```bash
terraform state pull > pre-import.tfstate    # backup
terraform import '<address>' '<cloud-id>'
terraform plan                                # iterate .tf until plan is empty
terraform apply
```

### 7.6 "Rotate a Key Vault secret consumed by pods"

```bash
az keyvault secret set --vault-name <vault> --name <name> --value "$NEW"
# akv2k8s syncs the K8s Secret automatically (watch the CRD):
kubectl get azurekeyvaultsecret -n <ns> -w
# Pods don't auto-reload — bounce the consumer:
kubectl rollout restart deployment/<svc> -n <ns>
```

### 7.7 "New VirtualService isn't taking effect"

```bash
istioctl analyze -n <ns>                        # syntactic / semantic issues
istioctl proxy-status                            # any sidecar STALE?
kubectl describe virtualservice <name> -n <ns>   # confirm hosts + gateways match
istioctl proxy-config route <ingress-pod> -n istio-system | grep <host>
kubectl logs <ingress-pod> -n istio-system -c istio-proxy --tail=100
```

---

## 8. Gotchas

- **Always pass `-n <ns>`.** Forgetting it on multi-tenant clusters returns
  "no resources found" or hits the wrong namespace.
- **Use `--file ./kubeconfig`** with `az aks get-credentials` to keep cluster
  contexts isolated per shell (`export KUBECONFIG=$PWD/kubeconfig`).
- **Flux owns the cluster.** Manual `kubectl apply`/`edit` will be reverted
  unless you `flux suspend` first. Don't forget to `flux resume`.
- **`flux reconcile … --with-source`** is what you almost always want;
  without `--with-source` Flux re-applies the *cached* revision.
- **PDBs block drains.** `kubectl get pdb -A` before any node operation.
- **`terraform state rm`** never deletes the cloud resource — pair it with
  `terraform state pull > backup.tfstate` every time.
- **Targeted `terraform apply -target=`** is a debugging tool, not a
  workflow. Always finish with an untargeted `plan`/`apply`.
- **K8s does not auto-roll on Secret/ConfigMap change.** `kubectl rollout
  restart deployment/<name>` after rotating values.
- **Use `--previous`** on `kubectl logs` to see *why* a pod crashed, not
  just what the new one is saying.
- **Istio `VirtualService` host suffixes matter.** `.<ns>.svc.cluster.local`
  must match the actual destination namespace; copy-pasting between
  environments (e.g. `ea` → `ga`) is a frequent source of routing bugs.
- **`STALE` sidecars** in `istioctl proxy-status` mean Envoy hasn't received
  the latest config from `istiod`; restart the pod or investigate `istiod`.
- **A namespace-wide `AuthorizationPolicy` with `action: DENY`** silently
  blackholes traffic — always run `kubectl get authorizationpolicy -A`
  after a 403 spike.
- **Missing `istio-proxy` sidecar** ⇒ the namespace lacks
  `istio-injection=enabled`, or the pod opted out via
  `sidecar.istio.io/inject: "false"`.
