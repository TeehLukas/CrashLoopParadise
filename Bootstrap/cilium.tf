locals {
  kubernetes_credentials = module.talos.kubeconfig.kubernetes_client_configuration

  # Version, Values und Gateway kommen aus dem Argo-CD-Tool-Ordner: eine Quelle für
  # Erstinstallation (Terraform) und Betrieb (Argo CD).
  cilium_dir    = "${path.module}/../ArgoCD/Infrastructure/cilium"
  cilium_config = yamldecode(file("${local.cilium_dir}/config.yaml"))
}

# Nur die Erstinstallation: Danach verwaltet Argo CD die Release (App cilium-in-cluster).
# ignore_changes = all, damit Terraform Argo CD nie zurückdreht.
resource "helm_release" "cilium" {
  name       = local.cilium_config.app
  namespace  = local.cilium_config.namespace
  repository = local.cilium_config.chart.repo
  chart      = local.cilium_config.chart.name
  version    = local.cilium_config.chart.version
  values     = [file("${local.cilium_dir}/values.yaml")]
  wait       = true
  timeout    = 600

  lifecycle {
    ignore_changes = all
  }
}

resource "kubectl_manifest" "cilium_gateway" {
  yaml_body = file("${local.cilium_dir}/manifests/gateway.yaml")

  lifecycle {
    ignore_changes = all
  }

  depends_on = [helm_release.cilium]
}
