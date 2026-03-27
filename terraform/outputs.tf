output "controlplane_ip" {
  value = [
    for addr in flatten(proxmox_virtual_environment_vm.talos["talos-cp-1"].ipv4_addresses) :
    addr if addr != "127.0.0.1" && addr != "" && !startswith(addr, "169.254.")
  ][0]
}

output "worker_ips" {
  value = [
    for k, v in proxmox_virtual_environment_vm.talos :
    [
      for addr in flatten(v.ipv4_addresses) :
      addr if addr != "127.0.0.1" && addr != "" && !startswith(addr, "169.254.")
    ][0]
    if k != "talos-cp-1"
  ]
}
