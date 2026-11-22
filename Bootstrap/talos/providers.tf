terraform {
  required_version = ">= 1.7"

  required_providers {
    talos = {
      source  = "siderolabs/talos"
      version = "0.13.0-alpha.2"
    }
  }
}
