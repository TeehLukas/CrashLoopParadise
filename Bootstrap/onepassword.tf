# Legt die Admin-Kubeconfig zusätzlich als Secure Note im 1Password-Vault ab.
# Zugang über OP_SERVICE_ACCOUNT_TOKEN (wie in der Taskfile). Der Service Account
# braucht Schreibrechte auf den Vault.
data "onepassword_vault" "kubernetes" {
  name = var.onepassword_vault
}

resource "onepassword_item" "kubeconfig" {
  vault      = data.onepassword_vault.kubernetes.uuid
  title      = "kubeconfig-${var.cluster_name}"
  category   = "secure_note"
  note_value = module.talos.kubeconfig.kubeconfig_raw
  tags       = ["terraform", "kubeconfig"]
}
