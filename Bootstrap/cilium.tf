locals {
  kubernetes_credentials = module.talos.kubeconfig.kubernetes_client_configuration
}

# Nur der Bootstrap: Danach verwaltet Argo CD Cilium (siehe README).
resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.cilium_version
  values     = [file("${path.module}/kubernetes/cilium/values.yaml")]
  wait       = true
  timeout    = 600
}

resource "kubectl_manifest" "cilium_gateway" {
  yaml_body = file("${path.module}/kubernetes/gateway.yaml")

  depends_on = [helm_release.cilium]
}