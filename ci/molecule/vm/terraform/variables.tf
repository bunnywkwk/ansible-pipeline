variable "libvirt_uri" {
  type        = string
  description = "libvirt on the Jenkins host. Builds run there as jenkins (group libvirt). A separate KVM host needs only a new URI."
  default     = "qemu:///system"
}

variable "run_id" {
  type        = string
  description = "Unique name of this test run (molecule platform name); names the domain and its volumes."
}

variable "hostname" {
  type    = string
  default = "el9-vm"
}

variable "pool" {
  type    = string
  default = "ci"
}

variable "golden_volume" {
  type    = string
  default = "rhel9-golden.qcow2"
}

variable "network" {
  type    = string
  default = "default"
}

variable "memory_mb" {
  type    = number
  default = 2048
}

variable "vcpu" {
  type    = number
  default = 2
}

# Empty defaults so a destroy works without them; create.yml checks they are set before an apply.
variable "ssh_public_key" {
  type    = string
  default = ""
}

variable "rhsm_org" {
  type      = string
  sensitive = true
  default   = ""
}

variable "rhsm_activation_key" {
  type      = string
  sensitive = true
  default   = ""
}
