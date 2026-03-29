# Homelab Kubernetes Cluster

A fully automated, Infrastructure-as-Code homelab Kubernetes cluster built on [Talos Linux](https://www.talos.dev/). Provisions a multi-node cluster across a Proxmox hypervisor and an optional desktop KVM worker, then deploys a full GitOps stack with monitoring, storage, and ingress — all from a single command.

## Architecture

```
                          Internet
                              │
                      Cloudflare Proxy
                              │
                     ┌────────────────┐
                     │  Router / NAT  │
                     │  Port 443 →    │
                     │  192.168.0.210 │
                     └────────┬───────┘
                              │
              Home Network (192.168.0.0/24)
                              │
          ┌───────────────────┼────────────────────┐
          │                   │                    │
  ┌───────────────┐   ┌───────────────┐   ┌────────────────────┐
  │  Proxmox Host │   │  Proxmox Host │   │  Desktop (Manjaro) │
  │               │   │               │   │                    │
  │  talos-cp-1   │   │  talos-w-1    │   │  talos-desktop     │
  │  Control Plane│   │  Worker       │   │  Worker (KVM)      │
  │  .201         │   │  .202         │   │  .204              │
  │  2vCPU / 4GB  │   │  2vCPU / 4GB  │   │  8vCPU / 16GB      │
  │  50GB disk    │   │  50GB disk    │   │  20GB disk         │
  └───────────────┘   └───────────────┘   └────────────────────┘
                              │
                      talos-w-2  .203
                      Worker
                      2vCPU / 4GB / 50GB
```

**Kubernetes:** v1.35.2 | **Talos:** v1.12.6 | **Pod CIDR:** 10.244.0.0/16 | **Service CIDR:** 10.96.0.0/12

## Toolchain

| Tool                                                  | Role                                                                            |
| ----------------------------------------------------- | ------------------------------------------------------------------------------- |
| [Terraform](https://www.terraform.io/)                | Provisions VMs on Proxmox (BPG provider) and desktop KVM (libvirt provider)     |
| [Ansible](https://www.ansible.com/)                   | Bootstraps the Talos cluster — generates configs, applies them, bootstraps etcd |
| [Talos Linux](https://www.talos.dev/)                 | Immutable, minimal Linux OS purpose-built for Kubernetes                        |
| [Helm](https://helm.sh/)                              | Deploys bootstrap components (Longhorn, Sealed Secrets, ArgoCD)                 |
| [ArgoCD](https://argoproj.github.io/cd/)              | GitOps controller — syncs all Kubernetes apps from this repo                    |
| [Sealed Secrets](https://sealed-secrets.netlify.app/) | Encrypts secrets for safe storage in git                                        |
| [Task](https://taskfile.dev/)                         | Top-level workflow orchestration                                                |

## Kubernetes Stack

| App                                                                          | Namespace       | Role                                                      |
| ---------------------------------------------------------------------------- | --------------- | --------------------------------------------------------- |
| [Longhorn](https://longhorn.io/)                                             | longhorn-system | Distributed block storage / default StorageClass          |
| [MetalLB](https://metallb.universe.tf/)                                      | metallb-system  | LoadBalancer IPs for bare metal (pool: 192.168.0.210-220) |
| [ingress-nginx](https://kubernetes.github.io/ingress-nginx/)                 | ingress-nginx   | Reverse proxy / ingress controller                        |
| [cert-manager](https://cert-manager.io/)                                     | cert-manager    | Automatic TLS certs via Let's Encrypt + Cloudflare DNS-01 |
| [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts) | monitoring      | Prometheus + Grafana                                      |

## How It Works

```
task up
 │
 ├─ 1. Terraform → Create VMs on Proxmox
 │
 ├─ 2. Ansible
 │      ├─ Generate Talos machine configs (talosctl gen config)
 │      ├─ Push configs to each node (talosctl apply-config)
 │      ├─ Bootstrap etcd on the control plane
 │      ├─ Fetch kubeconfig → ~/.kube/config
 │      └─ Wait for all nodes Ready
 │
 ├─ 3. k8s-install (install.sh)
 │      ├─ Pre-create privileged namespaces
 │      ├─ Install Longhorn via Helm (bootstrapped before ArgoCD)
 │      ├─ Install Sealed Secrets controller
 │      └─ Install ArgoCD
 │
 ├─ 4. seal-secrets
 │      ├─ Encrypt secrets with cluster public key (kubeseal)
 │      └─ Commit sealed secret files to git
 │
 └─ 5. gitops-handoff
        └─ Apply root ArgoCD app → ArgoCD syncs everything else from git
```

After handoff, all cluster state is driven by git. Pushing a change to any `values.yaml` triggers an automatic sync.

## Repository Structure

```
.
├── terraform/               # Proxmox VM provisioning
├── terraform-desktop/       # Desktop KVM worker provisioning (libvirt)
├── ansible/
│   ├── site.yaml            # Main cluster bootstrap playbook
│   ├── desktop-join.yaml    # Desktop worker join playbook
│   ├── setup-desktop-host.yaml  # One-time host setup (KVM, bridge networking)
│   └── inventory.py         # Dynamic inventory from Terraform outputs
├── talos/
│   ├── patches/             # Talos machine config patches
│   └── generated/           # Generated configs (gitignored)
├── kubernetes/
│   ├── apps/                # ArgoCD Application manifests
│   ├── argocd/              # ArgoCD Helm values
│   ├── cert-manager/        # cert-manager values + ClusterIssuer
│   ├── config/              # Shared cluster config (domain, IPs, email)
│   ├── ingress-nginx/       # ingress-nginx values
│   ├── longhorn/            # Longhorn values
│   ├── metallb/             # MetalLB values + IP pool
│   ├── monitoring/          # kube-prometheus-stack values
│   ├── secrets/             # Sealed secrets (safe to commit)
│   ├── install.sh           # Bootstrap script
│   ├── seal-secrets.sh      # Generate sealed secrets
│   └── gitops-handoff.sh    # Apply root ArgoCD app
└── Taskfile.yaml
```

## Prerequisites

- Proxmox host with API token
- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/)
- [talosctl](https://www.talos.dev/latest/introduction/getting-started/)
- [Helm](https://helm.sh/docs/intro/install/)
- [kubeseal](https://github.com/bitnami-labs/sealed-secrets#kubeseal)
- [Task](https://taskfile.dev/installation/)
- [kubectl](https://kubernetes.io/docs/reference/kubectl/)

## Usage

### First-time setup

```bash
# Fill in Proxmox credentials
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Fill in secrets
cp kubernetes/.env.example kubernetes/.env
chmod 600 kubernetes/.env
# edit kubernetes/.env — CF_API_TOKEN and GRAFANA_PASSWORD

# Edit shared config (domain, IPs, email)
# kubernetes/config/kustomization.yaml
```

### Bring up the cluster

```bash
task up
```

This provisions the VMs, bootstraps Talos, installs the GitOps stack, seals and commits secrets, then hands off to ArgoCD.

### Verify

```bash
kubectl get nodes
kubectl get applications -n argocd
```

Services come up at:

- `grafana.ayyystew.com` — Grafana (monitoring)
- `argocd.ayyystew.com` — ArgoCD UI

### Add the desktop worker (optional)

```bash
task setup-desktop   # one-time: installs KVM, creates bridge (requires sudo)
task desktop-up      # provisions the VM and joins it to the cluster
```

### Tear down

```bash
task destroy         # destroy Proxmox VMs
task desktop-down    # drain and destroy the desktop worker
```

## Design Decisions

**Talos Linux** — Purpose-built for Kubernetes with no shell, no SSH, and a read-only filesystem. All configuration is declarative via API, making nodes immutable and fully reproducible.

**GitOps with ArgoCD** — All Kubernetes application state lives in this repo. ArgoCD watches the `master` branch and reconciles the cluster to match. No manual `kubectl apply` or `helm upgrade` after bootstrap.

**Sealed Secrets** — Secrets are encrypted with the cluster's public key and committed to git. Safe to store in a public repo. Must be re-sealed after a cluster rebuild.

**Longhorn bootstrapped before ArgoCD** — Longhorn's Helm chart includes a pre-upgrade job that requires RBAC resources which only exist after the chart installs them. This creates a chicken-and-egg problem on first install with ArgoCD. Longhorn is installed via Helm in `install.sh` and ArgoCD adopts it afterward.

**Cloudflare proxy** — All public services are fronted by Cloudflare. Real home IP is never exposed. cert-manager uses Cloudflare's DNS-01 challenge for Let's Encrypt, so port 80 never needs to be forwarded.

**Dynamic Ansible inventory** — `ansible/inventory.py` reads IP addresses directly from Terraform state at runtime. No manual inventory management when VMs change.

**Talos factory images** — Custom OS images via the [Talos image factory](https://factory.talos.dev) with `iscsi-tools` (required for Longhorn) and `qemu-guest-agent` extensions baked in.

**Desktop worker** — The desktop machine joins the cluster as a high-resource worker (8 vCPU, 16 GB RAM) via a KVM VM bridged onto the home network. Optional — the cluster runs fine without it.
