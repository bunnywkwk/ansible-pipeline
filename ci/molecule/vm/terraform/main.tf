# One test VM on the Jenkins host's KVM: copy-on-write disk from the golden image, cloud-init for the login and the
# Red Hat registration (the role's dnf tasks need it). Driven by create.yml and destroy.yml.
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.8.3"
    }
  }
}

provider "libvirt" {
  uri = var.libvirt_uri
}

resource "libvirt_volume" "disk" {
  name             = "${var.run_id}.qcow2"
  pool             = var.pool
  base_volume_name = var.golden_volume
  base_volume_pool = var.pool
}

resource "libvirt_cloudinit_disk" "seed" {
  name = "${var.run_id}-seed.iso"
  pool = var.pool

  # Root login with this run's key only (the VM is thrown away after the test); same user as the containers.
  user_data = <<-EOT
    #cloud-config
    hostname: ${var.hostname}
    disable_root: false
    ssh_pwauth: false
    ssh_authorized_keys:
      - ${trimspace(var.ssh_public_key)}
    rh_subscription:
      org: "${var.rhsm_org}"
      activation-key: "${var.rhsm_activation_key}"
  EOT
}

resource "libvirt_domain" "vm" {
  name    = var.run_id
  memory  = var.memory_mb
  vcpu    = var.vcpu
  machine = "q35"
  running = true

  cpu {
    mode = "host-passthrough"
  }

  # UEFI, like the golden image build.
  firmware = "/usr/share/edk2/ovmf/OVMF_CODE.fd"
  nvram {
    file     = "/var/lib/libvirt/qemu/nvram/${var.run_id}_VARS.fd"
    template = "/usr/share/edk2/ovmf/OVMF_VARS.fd"
  }

  disk {
    volume_id = libvirt_volume.disk.id
  }

  disk {
    volume_id = split(";", libvirt_cloudinit_disk.seed.id)[0]
  }

  network_interface {
    network_name   = var.network
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }
}
