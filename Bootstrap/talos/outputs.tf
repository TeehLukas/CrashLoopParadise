output "client_configuration" {
  description = "Talos-Client-Konfiguration (talosconfig)."
  value       = data.talos_client_configuration.this
  sensitive   = true
}

output "kubeconfig" {
  description = "Admin-Kubeconfig des Clusters."
  value       = talos_cluster_kubeconfig.this
  sensitive   = true
}

output "machine_config" {
  description = "Generierte Machine-Config je Node."
  value       = data.talos_machine_configuration.this
  sensitive   = true
}

output "installer_image" {
  description = "Installer-Image aus der Image Factory, das in den Machine-Configs eingetragen ist."
  value       = local.installer_image
}

output "iso_url" {
  description = "Metal-ISO aus der Image Factory zum Booten der Maschinen in den Maintenance-Modus."
  value       = local.iso_url
}
