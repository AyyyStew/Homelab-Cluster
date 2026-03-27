locals {
  talos_installer_iso_url = "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.12.6/metal-amd64.iso"
}

# ===================================================================
# Volumes - Terraform will download from the factory
# ===================================================================

resource "libvirt_volume" "talos_installer_iso" {
  name = "talos-installer.iso"
  pool = "default"
  target = {
    format = {
      type = "iso"
    }
  }

  create = {
    content = {
      url = local.talos_installer_iso_url
    }
  }
}

resource "libvirt_volume" "desktop_worker_disk" {
  name          = "talos-desktop-worker.qcow2"
  pool          = "default"
  capacity      = 20
  capacity_unit = "GiB"
  target = {
    format = {
      type = "qcow2"
    }
  }
}

# ===================================================================
# Virtual Machine
# ===================================================================

resource "libvirt_domain" "desktop_worker" {
  name    = "talos-desktop-worker"
  memory  = 16777216 # 16 GiB in KiB
  vcpu    = 8
  type    = "kvm"
  running = true

  cpu = {
    mode = "host-passthrough"
  }

  os = {
    type = "hvm"
  }

  devices = {
    disks = [
      # 1. Installer ISO (cdrom) - used for initial installation
      {
        device = "cdrom"
        boot = {
          order = 2
        }
        target = {
          dev = "hda"
          bus = "ide"
        }
        source = {
          volume = {
            pool   = libvirt_volume.talos_installer_iso.pool
            volume = libvirt_volume.talos_installer_iso.name
          }
        }
      },

      # 2. Main Talos disk (will be installed to or booted from)
      {
        device = "disk"
        boot = {
          order = 1
        }
        target = {
          dev = "sda"
          bus = "sata"
        }
        source = {
          volume = {
            pool   = libvirt_volume.desktop_worker_disk.pool
            volume = libvirt_volume.desktop_worker_disk.name
          }
        }
        driver = {
          type = "qcow2"
        }
      }
    ]

    interfaces = [
      {
        type = "bridge"
        source = {
          bridge = {
            bridge = "br0"
          }
        }
        model = {
          type = "virtio"
        }
        mac = {
          address = "bc:24:11:00:00:04"
        }
      }
    ]

    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      }
    ]

    consoles = [
      {
        type        = "pty"
        target_type = "serial"
        target_port = "0"
      }
    ]
  }
}

output "domain_id" {
  value = libvirt_domain.desktop_worker.id
}

output "instructions" {
  value = <<-EOF
    Talos VM created successfully!

    1. Connect to serial console:
       virsh console talos-desktop-worker

    2. Or use VNC (find port with: virsh domdisplay talos-desktop-worker)

    3. Apply your machine config with talosctl:
       talosctl apply-config --insecure --nodes <IP> --file controlplane.yaml   (or worker.yaml)

    Note: First boot from the ISO (cdrom). After installation completes,
    you can optionally remove the cdrom disk from the VM.
  EOF
}
