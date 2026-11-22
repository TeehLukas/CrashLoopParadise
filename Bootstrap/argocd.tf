locals {
  # Version und Values kommen aus dem Argo-CD-Tool-Ordner (siehe cilium.tf).
  argocd_dir    = "${path.module}/../ArgoCD/Infrastructure/argocd"
  argocd_config = yamldecode(file("${local.argocd_dir}/config.yaml"))
}

# Nur die Erstinstallation, mit HTTPRoute am Gateway "cilium-gateway" (cilium.tf).
# Danach verwaltet Argo CD sich selbst (App argocd-in-cluster).
resource "helm_release" "argocd" {
  name             = local.argocd_config.app
  namespace        = local.argocd_config.namespace
  create_namespace = true
  repository       = local.argocd_config.chart.repo
  chart            = local.argocd_config.chart.name
  version          = local.argocd_config.chart.version
  values           = [file("${local.argocd_dir}/values.yaml")]
  wait             = true
  timeout          = 600

  lifecycle {
    ignore_changes = all
  }

  depends_on = [kubectl_manifest.cilium_gateway]
}
