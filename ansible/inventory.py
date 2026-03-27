#!/usr/bin/env python3
"""Dynamic inventory reading Terraform outputs from all cluster node sources."""
import json
import os
import subprocess
import sys

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TERRAFORM_DIR = os.path.join(REPO_DIR, 'terraform')
TERRAFORM_DESKTOP_DIR = os.path.join(REPO_DIR, 'terraform-desktop')


def get_terraform_outputs(directory):
    result = subprocess.run(
        ['terraform', 'output', '-json'],
        cwd=directory,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    return json.loads(result.stdout)


def build_inventory():
    proxmox = get_terraform_outputs(TERRAFORM_DIR)
    desktop = get_terraform_outputs(TERRAFORM_DESKTOP_DIR)

    hostvars = {}
    cp_hosts = []

    proxmox_worker_hosts = []
    desktop_hosts = []

    if proxmox:
        cp_ip = proxmox['controlplane_ip']['value']
        worker_ips = proxmox['worker_ips']['value']

        cp_hosts.append('talos-cp-1')
        hostvars['talos-cp-1'] = {
            'ansible_host': cp_ip,
            'ansible_connection': 'local',
            'talos_role': 'controlplane',
        }

        for i, ip in enumerate(worker_ips, 1):
            name = f'talos-w-{i}'
            proxmox_worker_hosts.append(name)
            hostvars[name] = {
                'ansible_host': ip,
                'ansible_connection': 'local',
                'talos_role': 'worker',
            }

    if desktop:
        desktop_hosts.append('talos-desktop')
        hostvars['talos-desktop'] = {
            'ansible_host': desktop['desktop_worker_ip']['value'],
            'ansible_connection': 'local',
            'talos_role': 'worker',
        }

    return {
        'controlplane': {'hosts': cp_hosts},
        'proxmox_workers': {'hosts': proxmox_worker_hosts},
        'desktop': {'hosts': desktop_hosts},
        '_meta': {'hostvars': hostvars},
    }


def main():
    print(json.dumps(build_inventory(), indent=2))


if __name__ == '__main__':
    if '--host' in sys.argv:
        print(json.dumps({}))
    else:
        main()
