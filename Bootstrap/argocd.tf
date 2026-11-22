# Argo CD mit HTTPRoute für die UI am Gateway "cilium-gateway" (siehe gateway.tf).
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.argocd_version
  values           = [file("${path.module}/kubernetes/argocd/values.yaml")]
  wait             = true
  timeout          = 600

  depends_on = [kubectl_manifest.cilium_gateway]
}
