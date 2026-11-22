resource "local_sensitive_file" "machine_config" {
  for_each = var.nodes

  filename             = "${path.module}/output/talos-machine-config-${each.key}.yaml"
  content              = module.talos.machine_config[each.key].machine_configuration
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "local_sensitive_file" "talosconfig" {
  filename             = "${path.module}/output/talosconfig"
  content              = module.talos.client_configuration.talos_config
  file_permission      = "0600"
  directory_permission = "0700"
}

resource "local_sensitive_file" "kubeconfig" {
  filename             = "${path.module}/output/kubeconfig"
  content              = module.talos.kubeconfig.kubeconfig_raw
  file_permission      = "0600"
  directory_permission = "0700"
}

output "kubeconfig" {
  description = "Admin-Kubeconfig des Clusters."
  value       = module.talos.kubeconfig.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "Talos-Client-Konfiguration."
  value       = module.talos.client_configuration.talos_config
  sensitive   = true
}

output "node_ips" {
  description = "Statische IP-Adressen aller Nodes, nach Name."
  value       = { for name, node in var.nodes : name => node.ip }
}

output "installer_image" {
  description = "Installer-Image aus der Image Factory."
  value       = module.talos.installer_image
}

output "iso_url" {
  description = "Metal-ISO zum Booten der Maschinen in den Maintenance-Modus."
  value       = module.talos.iso_url
}

output "argocd_url" {
  description = "Adresse der Argo-CD-Oberfläche im Heimnetz."
  value       = "https://${yamldecode(file("${local.argocd_dir}/values.yaml")).global.domain}"
}
