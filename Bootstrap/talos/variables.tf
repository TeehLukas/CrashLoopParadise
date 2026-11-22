variable "cluster" {
  description = "Clusterweite Einstellungen."
  type = object({
    name                = string
    endpoint            = string
    vip                 = string
    talos_version       = string
    kubernetes_version  = string
    gateway_api_version = string
  })
}

variable "install" {
  description = "Installationsoptionen für alle Nodes."
  type = object({
    secure_boot    = bool
    tpm_encryption = bool
    wipe_disk      = bool
  })
}

variable "network" {
  description = "Gemeinsames IPv4-Präfix, Gateway und DNS für die statischen Node-IPs."
  type = object({
    prefix_length = number
    gateway       = string
    nameservers   = list(string)
  })
}

variable "nodes" {
  description = "Talos-Nodes nach Name."
  type = map(object({
    role         = string
    ip           = string
    interface    = string
    install_disk = string
    bootstrap    = bool
    labels       = map(string)
  }))
}

variable "dhcp_ips" {
  description = "Maintenance-IPv4 je Node-Name für die Erstinstallation."
  type        = map(string)
}
