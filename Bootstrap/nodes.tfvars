# Beispielwerte vor dem Apply an dein Netz und deine Hardware anpassen.
# Freie VIP im gemeinsamen Subnetz der Control Planes, außerhalb des DHCP-Pools.
vip = "192.168.10.100"

static_network = {
  prefix_length = 24
  gateway       = "192.168.10.1"
  nameservers   = ["192.168.10.1"]
}

# Maintenance-Adressen aus dem DHCP, unter denen noch nicht installierte Maschinen nach dem
# Boot der ISO erreichbar sind (Schlüssel wie in `nodes`). Bereits installierte Nodes
# brauchen keinen Eintrag; ohne Eintrag gilt die statische IP.
#dhcp_ips = {
#  controlplane-02 = "192.168.10.95"
#  controlplane-03 = "192.168.10.96"
#  worker-01       = "192.168.10.97"
#  worker-02       = "192.168.10.98"
#}

# Der Map-Schlüssel ist zugleich der Hostname (cp-01, worker-01, ...).
# Optional je Node: labels (z. B. topology.kubernetes.io/zone).
nodes = {
  controlplane-01 = {
    interface    = "eno1"
    role         = "control"
    ip           = "192.168.10.101"
    install_disk = "/dev/nvme0n1"
    bootstrap    = true
  }
  controlplane-02 = {
    interface    = "eno1"
    role         = "control"
    ip           = "192.168.10.102"
    install_disk = "/dev/nvme0n1"
  }
  controlplane-03 = {
    interface    = "eno1"
    role         = "control"
    ip           = "192.168.10.103"
    install_disk = "/dev/nvme0n1"
  }
  worker-01 = {
    interface    = "eno1"
    role         = "worker"
    ip           = "192.168.10.104"
    install_disk = "/dev/nvme0n1"
  }
  worker-02 = {
    interface    = "eno1"
    role         = "worker"
    ip           = "192.168.10.105"
    install_disk = "/dev/nvme0n1"
  }
}
