locals {
  # "v1.14.6" -> "v1.14": Der Provider erwartet die Config-Contract-Version.
  talos_contract = join(".", slice(split(".", var.cluster.talos_version), 0, 2))

  bootstrap_node    = one([for node in values(var.nodes) : node if node.bootstrap])
  control_plane_ips = [for node in values(var.nodes) : node.ip if node.role != "worker"]
  worker_ips        = [for node in values(var.nodes) : node.ip if node.role == "worker"]

  # Nodes, deren Erstkonfiguration über die DHCP-Adresse im Maintenance-Modus läuft.
  maintenance_nodes = {
    for name, node in var.nodes : name => node
    if lookup(var.dhcp_ips, name, node.ip) != node.ip
  }

  # Secure Boot braucht die signierten Images (ISO und Installer).
  installer_image = var.install.secure_boot ? data.talos_image_factory_urls.this.urls.installer_secureboot : data.talos_image_factory_urls.this.urls.installer
  iso_url         = var.install.secure_boot ? data.talos_image_factory_urls.this.urls.iso_secureboot : data.talos_image_factory_urls.this.urls.iso

  # Reihenfolge ist relevant: Erst die generierten Standardwerte entfernen, dann
  # Rollen- und Node-Einstellungen setzen.
  config_patches = {
    for name, node in var.nodes : name => concat(
      [file("${path.module}/machine-config/reset-hostname.yaml")],
      var.install.tpm_encryption ? [file("${path.module}/machine-config/tpm-encryption.yaml")] : [],
      node.role == "worker" ? (
        length(node.labels) > 0 ? [
          templatefile("${path.module}/machine-config/worker.yaml.tftpl", { node = node })
        ] : []
        ) : [
        file("${path.module}/machine-config/reset-control-plane-node.yaml"),
        templatefile("${path.module}/machine-config/control-plane.yaml.tftpl", {
          node                              = node
          gateway_api_url                   = "https://github.com/kubernetes-sigs/gateway-api/releases/download/${var.cluster.gateway_api_version}/standard-install.yaml"
          kubelet_serving_cert_approver_url = "https://raw.githubusercontent.com/alex1989hu/kubelet-serving-cert-approver/${var.cluster.kubelet_serving_cert_approver_version}/deploy/standalone-install.yaml"
          metrics_server_url                = "https://github.com/kubernetes-sigs/metrics-server/releases/download/${var.cluster.metrics_server_version}/components.yaml"
        }),
      ],
      [templatefile("${path.module}/machine-config/common.yaml.tftpl", {
        node            = node
        hostname        = name
        network         = var.network
        vip             = var.cluster.vip
        installer_image = local.installer_image
        wipe_disk       = var.install.wipe_disk
      })],
    )
  }
}

resource "talos_machine_secrets" "this" {
  talos_version = local.talos_contract
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster.name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_plane_ips
  nodes                = [for node in values(var.nodes) : node.ip]
}

data "talos_machine_configuration" "this" {
  for_each = var.nodes

  cluster_name       = var.cluster.name
  cluster_endpoint   = var.cluster.endpoint
  machine_type       = each.value.role == "worker" ? "worker" : "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = local.talos_contract
  kubernetes_version = var.cluster.kubernetes_version

  config_patches = local.config_patches[each.key]

  lifecycle {
    precondition {
      condition     = alltrue([for name in keys(var.dhcp_ips) : contains(keys(var.nodes), name)])
      error_message = "dhcp_ips darf nur Node-Schlüssel aus nodes enthalten."
    }

    precondition {
      condition     = alltrue([for name, ip in var.dhcp_ips : ip != var.cluster.vip && (name == each.key || ip != each.value.ip)])
      error_message = "DHCP-Adressen dürfen weder die VIP noch die statische IP eines anderen Nodes belegen."
    }

    precondition {
      condition     = each.value.ip != var.cluster.vip
      error_message = "Die VIP muss eine separate Adresse sein und darf keiner Node-IP entsprechen."
    }
  }
}

# Nur beim Wechsel der Adresse: Erstinstallation über den Maintenance-Endpunkt.
resource "talos_machine_configuration_apply" "maintenance" {
  for_each = local.maintenance_nodes

  endpoint                    = var.dhcp_ips[each.key]
  node                        = var.dhcp_ips[each.key]
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration

  lifecycle {
    ignore_changes = [endpoint, node, machine_configuration_input]
  }
}

resource "talos_machine_configuration_apply" "this" {
  for_each   = var.nodes
  depends_on = [talos_machine_configuration_apply.maintenance]

  endpoint                    = each.value.ip
  node                        = each.value.ip
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.this[each.key].machine_configuration
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.this]

  endpoint             = local.bootstrap_node.ip
  node                 = local.bootstrap_node.ip
  client_configuration = talos_machine_secrets.this.client_configuration
}

# Wartet, bis die Nodes gebootet sind und etcd läuft. Die Kubernetes-Checks entfallen,
# denn die Nodes werden erst Ready, wenn Cilium per Helm installiert ist.
#
# Wichtig für Idempotenz: Die Abhängigkeit auf talos_machine_configuration_apply.this ist
# direkt. Terraform verschiebt das Lesen einer Data Source nur dann auf die Apply-Phase,
# wenn eine *direkte* depends_on-Ressource Änderungen im Plan hat. Mit nur
# talos_machine_bootstrap (ohne Änderung) würde der Check schon beim Plan laufen und auf
# noch nicht konfigurierte, neu hinzugefügte Nodes warten.
data "talos_cluster_health" "this" {
  depends_on = [
    talos_machine_configuration_apply.this,
    talos_machine_bootstrap.this,
  ]

  skip_kubernetes_checks = true

  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_plane_ips
  control_plane_nodes  = local.control_plane_ips
  worker_nodes         = local.worker_ips

  timeouts = {
    read = "15m"
  }
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [data.talos_cluster_health.this]

  endpoint             = local.bootstrap_node.ip
  node                 = local.bootstrap_node.ip
  client_configuration = talos_machine_secrets.this.client_configuration
}
