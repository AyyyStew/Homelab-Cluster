#!/usr/bin/env python3
"""Dynamic inventory that reads Terraform outputs for Talos node IPs."""
import json
import os
import subprocess
import sys

TERRAFORM_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'terraform')


def get_terraform_outputs():
    result = subprocess.run(
        ['terraform', 'output', '-json'],
        cwd=TERRAFORM_DIR,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return None
    return json.loads(result.stdout)


def build_inventory(outputs):
    cp_ip = outputs['controlplane_ip']['value']
    worker_ips = outputs['worker_ips']['value']

    hostvars = {
        'talos-cp-1': {
            'ansible_host': cp_ip,
            'ansible_connection': 'local',
            'talos_role': 'controlplane',
        }
    }

    worker_hosts = []
    for i, ip in enumerate(worker_ips, 1):
        name = f'talos-w-{i}'
        worker_hosts.append(name)
        hostvars[name] = {
            'ansible_host': ip,
            'ansible_connection': 'local',
            'talos_role': 'worker',
        }

    return {
        'controlplane': {'hosts': ['talos-cp-1']},
        'workers': {'hosts': worker_hosts},
        '_meta': {'hostvars': hostvars},
    }


def main():
    outputs = get_terraform_outputs()
    if outputs:
        print(json.dumps(build_inventory(outputs), indent=2))
    else:
        print(json.dumps({'_meta': {'hostvars': {}}}))


if __name__ == '__main__':
    if '--host' in sys.argv:
        print(json.dumps({}))
    else:
        main()
