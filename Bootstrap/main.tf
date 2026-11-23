locals {
  cluster_endpoint = coalesce(var.cluster_endpoint, "https://${var.vip}:6443")
}

module "talos" {
  source = "./talos"

  cluster = {
    name                = var.cluster_name
    endpoint            = local.cluster_endpoint
    vip                 = var.vip
    talos_version       = var.talos_version
    kubernetes_version  = var.kubernetes_version
    gateway_api_version = var.gateway_api_version

    metrics_server_version                = var.metrics_server_version
    kubelet_serving_cert_approver_version = var.kubelet_serving_cert_approver_version
  }

  install = {
    secure_boot    = var.secure_boot
    tpm_encryption = var.tpm_encryption
    wipe_disk      = var.wipe_install_disk
  }

  network  = var.static_network
  nodes    = var.nodes
  dhcp_ips = var.dhcp_ips
}
