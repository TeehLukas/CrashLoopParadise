variable "cluster_name" {
  description = "Name des neuen Talos-Clusters."
  type        = string
  default     = "CrashLoopParadise"
}

variable "onepassword_vault" {
  description = "Name des 1Password-Vaults, in den Terraform die Kubeconfig schreibt."
  type        = string
  default     = "Kubernetes"
}

variable "nodes" {
  description = "Talos-Nodes nach stabilem Namen mit Rolle, statischer IPv4-Adresse und Installationsdisk."
  type = map(object({
    role         = string
    ip           = string
    install_disk = string
    bootstrap    = optional(bool, false)
    interface    = string
    labels       = optional(map(string), {})
  }))

  validation {
    condition     = alltrue([for node in values(var.nodes) : trimspace(node.interface) != ""])
    error_message = "Jeder Node benötigt ein Netzwerkinterface."
  }

  validation {
    condition     = alltrue([for node in values(var.nodes) : contains(["control", "controlplane", "worker"], node.role)])
    error_message = "Die Rolle jedes Nodes muss control oder worker sein."
  }

  validation {
    condition = (
      length([for node in values(var.nodes) : node if node.bootstrap]) == 1 &&
      alltrue([for node in values(var.nodes) : contains(["control", "controlplane"], node.role) if node.bootstrap])
    )
    error_message = "Genau ein Control-Plane-Node muss bootstrap = true setzen."
  }

  validation {
    condition = (
      alltrue([for node in values(var.nodes) : can(cidrnetmask("${node.ip}/32"))]) &&
      length(distinct([for node in values(var.nodes) : node.ip])) == length(var.nodes)
    )
    error_message = "Jeder Node benötigt eine eindeutige IPv4-Adresse."
  }

  validation {
    condition = (
      alltrue([for name in keys(var.nodes) : can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", name))])
    )
    error_message = "Die Node-Schlüssel dienen als Hostname und müssen DNS-Labels sein: Kleinbuchstaben, Ziffern und Bindestriche, höchstens 63 Zeichen."
  }

  validation {
    condition     = alltrue([for node in values(var.nodes) : startswith(node.install_disk, "/dev/")])
    error_message = "Die Installationsdisk jedes Nodes muss als Gerätepfad unter /dev/ angegeben werden."
  }
}

variable "vip" {
  description = "Gemeinsame IPv4-Adresse für die Kubernetes-API auf allen Control-Plane-Nodes."
  type        = string
  nullable    = false

  validation {
    condition     = can(cidrnetmask("${var.vip}/32"))
    error_message = "vip muss eine IPv4-Adresse ohne Präfix sein."
  }
}

variable "static_network" {
  description = "Gemeinsames IPv4-Präfix, Gateway und DNS für statische Node-IPs."
  type = object({
    prefix_length = number
    gateway       = string
    nameservers   = list(string)
  })
  nullable = false

  validation {
    condition = (
      can(cidrnetmask("192.0.2.1/${var.static_network.prefix_length}")) &&
      can(cidrnetmask("${var.static_network.gateway}/32")) &&
      length(var.static_network.nameservers) > 0 &&
      alltrue([for address in var.static_network.nameservers : can(cidrnetmask("${address}/32"))])
    )
    error_message = "static_network benötigt ein gültiges IPv4-Präfix, ein IPv4-Gateway und mindestens einen IPv4-DNS-Server."
  }
}

variable "cluster_endpoint" {
  description = "Optionaler stabiler HTTPS-Endpunkt der Kubernetes-API, etwa ein Load Balancer. Standard ist die VIP auf Port 6443."
  type        = string
  default     = null
}

variable "talos_version" {
  description = "Talos-Version für Image Factory (Installer, ISO) und Machine-Config."
  type        = string
  default     = "v1.14.6"

  validation {
    condition     = can(regex("^v1\\.14\\.[0-9]+$", var.talos_version))
    error_message = "talos_version muss eine Talos-1.14-Version wie v1.14.6 sein."
  }
}

variable "secure_boot" {
  description = "Secure-Boot-Images (ISO und Installer) aus der Image Factory verwenden. Die Firmware muss dafür im Setup Mode sein, siehe README."
  type        = bool
  default     = true
}

variable "tpm_encryption" {
  description = "STATE und EPHEMERAL mit LUKS2 verschlüsseln, der Schlüssel liegt im TPM. Benötigt Secure Boot."
  type        = bool
  default     = true

  validation {
    condition     = !var.tpm_encryption || var.secure_boot
    error_message = "tpm_encryption setzt secure_boot = true voraus, sonst schützt PCR 7 nichts."
  }
}

variable "wipe_install_disk" {
  description = "Löscht die Installationsdisk bei der Installation (z. B. alte Windows-Partitionen). Wirkt nur bei der Erstinstallation."
  type        = bool
  default     = true
}


variable "gateway_api_version" {
  description = "Version der Gateway-API-CRDs, die Talos beim Bootstrap lädt. Cilium 1.20 ist gegen v1.6.3 getestet."
  type        = string
  default     = "v1.6.3"
}

variable "metrics_server_version" {
  description = "Version des metrics-server (components.yaml), den Talos beim Bootstrap lädt."
  type        = string
  default     = "v0.9.1"
}

variable "kubelet_serving_cert_approver_version" {
  description = "Version des kubelet-serving-cert-approver. Genehmigt die Serving-Zertifikate der Kubelets, die metrics-server braucht."
  type        = string
  default     = "v0.12.1"
}

variable "kubernetes_version" {
  description = "Kubernetes-Version für den Bootstrap."
  type        = string
  default     = "1.37.2"
}

variable "dhcp_ips" {
  description = "Maintenance-IPv4 (DHCP) je Node-Schlüssel, nur für Nodes, die noch nicht installiert sind. Fehlt ein Node, wird seine statische IP verwendet."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = (
      alltrue([for ip in values(var.dhcp_ips) : can(cidrnetmask("${ip}/32"))]) &&
      length(distinct(values(var.dhcp_ips))) == length(var.dhcp_ips)
    )
    error_message = "Jede DHCP-Adresse muss eine eindeutige IPv4-Adresse sein."
  }
}
