terraform {
  required_version = ">= 1.7"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.13.0-alpha.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.9"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3.0"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 3.0.1"
    }
  }
}

provider "helm" {
  kubernetes = {
    host                   = local.kubernetes_credentials.host
    cluster_ca_certificate = base64decode(local.kubernetes_credentials.ca_certificate)
    client_certificate     = base64decode(local.kubernetes_credentials.client_certificate)
    client_key             = base64decode(local.kubernetes_credentials.client_key)
  }
}

provider "kubectl" {
  host                   = local.kubernetes_credentials.host
  cluster_ca_certificate = base64decode(local.kubernetes_credentials.ca_certificate)
  client_certificate     = base64decode(local.kubernetes_credentials.client_certificate)
  client_key             = base64decode(local.kubernetes_credentials.client_key)
  load_config_file       = false
}
