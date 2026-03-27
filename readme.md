# Homelab Kubernetes Cluster

A fully automated, Infrastructure-as-Code homelab Kubernetes cluster built on [Talos Linux](https://www.talos.dev/). Provisions a multi-node cluster across a Proxmox hypervisor and an optional desktop KVM worker from a single command.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Home Network (192.168.0.0/24)         │
│                                                         │
│  ┌──────────────────────────┐  ┌─────────────────────┐  │
│  │     Proxmox Host         │  │   Desktop (Manjaro) │  │
│  │  ┌────────────────────┐  │  │  ┌───────────────┐  │  │
│  │  │ talos-cp-1         │  │  │  │talos-desktop  │  │  │
│  │  │ Control Plane      │  │  │  │worker         │  │  │
│  │  │ 192.168.0.201      │  │  │  │192.168.0.204  │  │  │
│  │  │ 2 vCPU / 4GB RAM   │  │  │  │8 vCPU / 16GB  │  │  │
│  │  └────────────────────┘  │  │  └───────────────┘  │  │
│  │  ┌────────────────────┐  │  │    KVM / libvirt    │  │
│  │  │ talos-w-1          │  │  └─────────────────────┘  │
│  │  │ Worker             │  │                           │
│  │  │ 192.168.0.202      │  │                           │
│  │  │ 2 vCPU / 2GB RAM   │  │                           │
│  │  └────────────────────┘  │                           │
│  │  ┌────────────────────┐  │                           │
│  │  │ talos-w-2          │  │                           │
│  │  │ Worker             │  │                           │
│  │  │ 192.168.0.203      │  │                           │
│  │  │ 2 vCPU / 2GB RAM   │  │                           │
│  │  └────────────────────┘  │                           │
│  └──────────────────────────┘                           │
└─────────────────────────────────────────────────────────┘
```

**Kubernetes:** v1.35.2 | **Talos:** v1.12.6 | **Pod CIDR:** 10.244.0.0/16 | **Service CIDR:** 10.96.0.0/12

## Toolchain

| Tool                                   | Role                                                                                                        |
| -------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| [Terraform](https://www.terraform.io/) | Provisions VMs on Proxmox (BPG provider) and desktop KVM (libvirt provider)                                 |
| [Ansible](https://www.ansible.com/)    | Orchestrates cluster bootstrap — generates Talos configs, applies them, bootstraps etcd, fetches kubeconfig |
| [Talos Linux](https://www.talos.dev/)  | Immutable, minimal Linux OS purpose-built for Kubernetes                                                    |
| [Task](https://taskfile.dev/)          | Top-level workflow orchestration; chains Terraform and Ansible into named tasks                             |

## How It Works

```
task up
 │
 ├─ 1. Terraform → Create VMs on Proxmox, output IPs
 │
 └─ 2. Ansible (site.yaml)
      ├─ Wait for Talos maintenance API (port 50000) on each node
      ├─ Generate Talos machine configs (talosctl gen config)
      ├─ Push configs to each node (talosctl apply-config)
      ├─ Bootstrap etcd on the control plane
      └─ Fetch kubeconfig → ~/.kube/config
```

The Ansible inventory is dynamic — it reads IP addresses directly from Terraform state outputs, so there's no manual IP management.

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
└── Taskfile.yml             # Task definitions
```

## Prerequisites

- Proxmox host with API token
- [Terraform](https://www.terraform.io/downloads) >= 1.0
- [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/)
- [talosctl](https://www.talos.dev/latest/introduction/getting-started/)
- [Task](https://taskfile.dev/installation/)
- `kubectl`

## Usage

### Bring up the cluster

```bash
# Copy and fill in your Proxmox credentials
cp terraform/terraform.tfvars.example terraform/terraform.tfvars

# Provision VMs and bootstrap the cluster
task up

# Verify
kubectl get nodes
```

### Add the desktop worker (optional)

The desktop worker runs as a KVM VM on the local machine, bridged onto the home network. One-time host setup:

```bash
task setup-desktop   # installs QEMU/KVM, creates br0 bridge (requires sudo)
```

Then:

```bash
task desktop-up      # provisions the VM and joins it to the cluster
```

### Tear down

```bash
task destroy          # destroy Proxmox VMs
task desktop-down     # drain and destroy the desktop worker
```

## Design Decisions

**Talos Linux** — Instead of a general-purpose OS, Talos is purpose-built for Kubernetes. It has no shell, no SSH, and a read-only filesystem. All configuration is done via a declarative API, making nodes immutable and reproducible.

**Dynamic Ansible inventory** — `ansible/inventory.py` calls `terraform output -json` at runtime. Adding or changing a VM in Terraform automatically makes it available to Ansible without touching inventory files.

**Talos factory images** — Custom OS images are built via the [Talos image factory](https://factory.talos.dev) with the `qemu-guest-agent` system extension, enabling guest IP reporting and graceful shutdown from the hypervisor.

**Desktop worker** — The desktop machine participates in the cluster as a high-resource worker (8 vCPU, 16 GB RAM) via a KVM VM bridged onto the home network. This lets the cluster use the desktop's resources when it's available without it being a permanent infrastructure dependency.
