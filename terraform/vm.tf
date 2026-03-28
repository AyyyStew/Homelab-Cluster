locals {
  nodes = {
    "talos-cp-1" = { vmid = 201, role = "controlplane", mac = "BC:24:11:00:00:01" }
    "talos-w-1"  = { vmid = 202, role = "worker", mac = "BC:24:11:00:00:02" }
    "talos-w-2"  = { vmid = 203, role = "worker", mac = "BC:24:11:00:00:03" }
  }
}

resource "proxmox_virtual_environment_download_file" "talos_iso" {
  content_type = "iso"
  datastore_id = "local"
  node_name    = "proxmox"
  url          = "https://factory.talos.dev/image/dc7b152cb3ea99b821fcb7340ce7168313ce393d663740b791c36f6e95fc8586/v1.12.6/metal-amd64.iso"
  file_name    = "talos-factory.iso"
}

resource "proxmox_virtual_environment_vm" "talos" {
  for_each  = local.nodes
  name      = each.key
  node_name = "proxmox"
  vm_id     = each.value.vmid

  cpu {
    cores = 2
    type  = "x86-64-v2-AES"
  }

  memory {
    dedicated = 4096
  }

  # Boot from Talos ISO
  cdrom {
    file_id   = proxmox_virtual_environment_download_file.talos_iso.id
    interface = "ide0"
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 50
  }

  network_device {
    bridge      = "vmbr0"
    model       = "virtio"
    mac_address = each.value.mac
  }

  boot_order = ["ide0", "scsi0"]

  agent {
    enabled = true
  }

}
