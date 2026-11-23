# Talos-Bootstrap auf Bare Metal

Terraform-Setup für einen Talos-Linux-Cluster (v1.14.6) auf eigener Hardware, ohne Proxmox oder andere Virtualisierung. Der Aufbau folgt dem Artikel [Talos, Proxmox und OpenTofu](https://blog.stonegarden.dev/articles/2024/08/talos-proxmox-tofu/): Ein `talos`-Modul erzeugt Image, Secrets, Machine-Configs, Bootstrap und Kubeconfig. Die virtuellen Maschinen des Artikels entfallen, stattdessen booten die Maschinen die Secure-Boot-ISO aus der Image Factory. Die Systemvolumes sind per TPM verschlüsselt. Cilium, das Gateway und Argo CD installiert Terraform einmalig per Helm-Release, danach verwaltet Argo CD alle drei (siehe [Übergabe an Argo CD](#übergabe-an-argo-cd)).

```
Bootstrap/
  providers.tf, variables.tf, main.tf, outputs.tf, nodes.tfvars
  cilium.tf                              Erstinstallation Cilium + Gateway
  argocd.tf                              Erstinstallation Argo CD
  talos/
    providers.tf, variables.tf, image.tf, config.tf, outputs.tf
    image/schematic.yaml                 System-Extensions für die Image Factory
    machine-config/
      common.yaml.tftpl                  Installation, Hostname, Netzwerk, VIP, KubePrism
      control-plane.yaml.tftpl           Cilium statt Flannel/kube-proxy, Gateway-API-CRDs
      worker.yaml.tftpl                  Node-Labels
      tpm-encryption.yaml                LUKS2 für STATE und EPHEMERAL, Schlüssel im TPM
      reset-*.yaml                       entfernen generierte Standardwerte vor den eigenen Patches
ArgoCD/Infrastructure/                   Version, Values, Manifeste (von Terraform gelesen)
  cilium/config.yaml, values.yaml        Cilium-Chart und -Values (nur Gateway API)
  cilium/manifests/gateway.yaml          Gateway cilium-gateway (HTTP + HTTPS)
  argocd/config.yaml, values.yaml        Argo-CD-Chart und -Values, HTTPRoute
```

## Hardware vorbereiten (HP EliteDesk 800 G5 Mini)

Die Geräte haben ein TPM 2.0 und UEFI mit Secure Boot. Die Schritte gelten für jede Maschine. Mach sie zuerst mit einem Gerät komplett durch (BIOS, Schlüssel eintragen, Installation, Neustart, Verschlüsselung prüfen) und richte danach die anderen ein.

1. **BIOS aktualisieren**, bevor du Talos installierst (F10, „Update System BIOS“ oder HP SoftPaq). Ein späteres Update kann die Secure-Boot-Schlüssel zurücksetzen, dann entsperrt das TPM die Platte nicht mehr.
2. **Werkseinstellungen:** Main, Apply Factory Defaults and Exit.
3. **TPM leeren:** Security, TPM Embedded Security. „TPM Device“ muss „Available“ und „TPM State“ „Enabled“ sein. Setze „Clear TPM“ auf „On next boot“ und bestätige das Löschen beim nächsten Start. Windows und BitLocker haben das TPM vorher benutzt.
4. **Secure Boot in den Setup Mode:** Advanced, Secure Boot Configuration, „Legacy Support Disable and Secure Boot Enable“, dann „Clear Secure Boot Keys“. Bestätige das beim nächsten Start mit dem angezeigten Code. Nur im Setup Mode kann Talos seine eigenen Schlüssel eintragen. Die Secure-Boot-Images sind mit dem Schlüssel von Sidero Labs signiert, mit den HP- und Microsoft-Schlüsseln würden sie nicht starten. Windows startet danach nicht mehr.
5. **Von der Secure-Boot-ISO booten** (F9 öffnet das Bootmenü). Im Setup Mode zeigt der Talos-Bootloader „Enroll Secure Boot keys: auto“. Wähle den Eintrag. Das Gerät trägt die Schlüssel ein, startet neu und wartet im Maintenance-Modus auf die Konfiguration.

Kontrolle im Maintenance-Modus, `SecureBoot` muss `true` sein:

```sh
talosctl -n <dhcp-ip> get securitystate --insecure
talosctl -n <dhcp-ip> get disks --insecure     # Disk-Pfad für install_disk prüfen
```

Nach dem Apply zeigt `talosctl --talosconfig=output/talosconfig -n <ip> get volumestatus` die LUKS2-Verschlüsselung von `STATE` und `EPHEMERAL`.

Die Verschlüsselung steuern drei Variablen:

| Variable | Standard | Wirkung |
| --- | --- | --- |
| `secure_boot` | `true` | Signierte ISO und Installer (`metal-installer-secureboot`) |
| `tpm_encryption` | `true` | LUKS2 für `STATE` und `EPHEMERAL`, setzt `secure_boot` voraus |
| `wipe_install_disk` | `true` | Löscht die Installationsdisk, also die alten Windows-Partitionen. Wirkt nur bei der Installation |

Talos erzeugt den LUKS2-Schlüssel selbst und versiegelt ihn im TPM. Er ist an PCR 7 (Secure-Boot-Zustand) und eine signierte PCR-11-Policy (gemessene Boot-Komponenten) gebunden. Longhorn legt seine Daten unter `/var/lib/longhorn` auf `EPHEMERAL` ab, sie sind also mitverschlüsselt.

Worauf du achten solltest:

- Mache Upgrades immer mit dem `installer-secureboot`-Image (Ausgabe `installer_image`). Dank der signierten PCR-11-Policy wird die Platte nach einem Upgrade weiter entsperrt.
- Secure Boot ausschalten, die Schlüssel löschen oder das TPM leeren lässt die Platte verschlossen, der Node muss dann neu installiert werden. Bei Kubernetes-Nodes ist das meist in Ordnung, weil Longhorn die Daten repliziert. Einen zweiten Schlüssel-Slot (zum Beispiel `nodeID`) als Notzugang habe ich bewusst weggelassen, er schwächt die Verschlüsselung deutlich.

## Ablauf

Die ISO für Schritt 5 der Hardware-Vorbereitung entsteht in Schritt 2 hier.

```sh
terraform apply -var-file=nodes.tfvars -var 'dhcp_ips={}' -target=module.talos.data.talos_image_factory_urls.this
terraform output -raw iso_url
```

1. Passe `talos/image/schematic.yaml` an. Aktiv sind `i915` (integrierte Grafik), `intel-ucode`, `iscsi-tools` und `util-linux-tools` (Longhorn) sowie `nfs-utils`. Die Extensions landen im Installer-Image und in der ISO.
2. Hole die ISO-URL mit den Befehlen oben. Der gezielte Apply registriert das Schematic in der Image Factory und braucht noch keine Maschinen. Schreibe die ISO auf einen USB-Stick, boote jede Maschine nach der Hardware-Vorbereitung davon und notiere ihre DHCP-Adresse. Der Terraform-Rechner braucht Zugriff auf die Talos-API der Nodes (TCP 50000, DHCP- und statische Adressen) und auf die Kubernetes-API (VIP, TCP 6443).
3. Passe `nodes.tfvars` an. Der Map-Schlüssel ist zugleich der Hostname, `cp-01` ergibt also den Hostnamen `cp-01`. Setze pro Maschine `role = "control"` oder `"worker"`, statische `ip`, `interface` und `install_disk`. Genau ein Control-Node bekommt `bootstrap = true`. Optional setzt `labels` Node-Labels, zum Beispiel `topology.kubernetes.io/zone`. Prüfe den Disk-Pfad auf jeder Maschine vor dem Apply.
4. Setze in `static_network` Präfix, Default-Gateway und DNS. Reserviere die statischen Adressen und eine freie `vip` im gemeinsamen Layer-2-Netz der Control Planes. Der Kubernetes-Endpunkt ist `https://<vip>:6443`. Ein expliziter `cluster_endpoint` überschreibt das.
5. Trage in `nodes.tfvars` unter `dhcp_ips` die DHCP-Adresse jeder noch nicht installierten Maschine ein, mit denselben Schlüsseln wie in `nodes`, zum Beispiel `{ cp-02 = "192.168.10.95" }`. Die Variable ist optional: Ohne Eintrag verwendet Terraform die statische IP des Nodes. Der DHCP-Pool vergibt die Adressen nach jedem ISO-Boot womöglich neu. Prüfe sie deshalb kurz vor dem Apply mit `talosctl get disks --insecure -n <ip> -e <ip>`.

```sh
cd Bootstrap
terraform init
terraform plan -var-file=nodes.tfvars -out=bootstrap.tfplan
terraform apply bootstrap.tfplan
```

Reihenfolge beim Apply:

1. Konfiguration anwenden. Bei einem Adresswechsel geht die Erstkonfiguration an die DHCP-Adresse, die dauerhafte Ressource nutzt die statische.
2. etcd auf dem markierten Control-Node bootstrappen.
3. `talos_cluster_health` prüft nur, ob die Nodes gebootet sind und etcd läuft. Die Kubernetes-Checks sind aus, denn die Nodes werden erst mit Cilium Ready. Der Check läuft bewusst erst nach der Konfiguration (direktes `depends_on` auf `talos_machine_configuration_apply.this`). Während neue Nodes installieren und neu starten, zeigt Terraform "Still reading..." an. Das kann einige Minuten dauern (Timeout 15 Minuten) und ist kein Hänger.
4. Kubeconfig holen und Cilium per Helm installieren.
5. Gateway `cilium-gateway` (HTTP und HTTPS) per `kubectl_manifest` direkt nach Cilium anwenden (kein Helm, kein Argo CD).
6. Argo CD per Helm installieren, samt HTTPRoute.

Terraform schreibt `talosconfig`, `kubeconfig` und die Machine-Configs nach `output/` mit Dateimodus 0600. State, gespeicherte Pläne und `output/` enthalten Zugangsdaten und sind nicht eingecheckt.

```sh
export KUBECONFIG=$PWD/output/kubeconfig
kubectl get nodes -o wide
kubectl get gatewayclass
talosctl --talosconfig=output/talosconfig -n 192.168.10.101 etcd members
```

## Nodes hinzufügen und dhcp_ips

Nach dem ersten Bootstrap sind die `dhcp_ips`-Einträge nicht mehr nötig. Du kannst sie löschen: Bereits konfigurierte Nodes erreicht Terraform über ihre statische `ip`. Ein `terraform plan` danach zeigt keine Änderung. Nur der Eintrag eines noch nicht installierten Nodes wird gebraucht.

So fügst du einen Node hinzu:

1. Hardware wie oben vorbereiten und die Maschine von der ISO in den Maintenance-Modus booten. Notiere die DHCP-Adresse und prüfe den Disk-Pfad. NVMe heißt `/dev/nvme0n1`. Ein USB-Stick (die ISO) kann als `/dev/sda` auftauchen, das ist nicht die Zielplatte.
2. Ergänze in `nodes.tfvars` einen Eintrag unter `nodes` mit einem neuen Schlüssel (Hostname), `role`, einer freien statischen `ip`, `interface` und `install_disk`. `bootstrap = true` bekommt nur der erste Control-Node, nie ein neuer.
3. Trage unter `dhcp_ips` die Maintenance-Adresse des neuen Nodes ein: `dhcp_ips = { worker-03 = "192.168.10.97" }`.
4. `terraform plan -var-file=nodes.tfvars`, dann `terraform apply`. Terraform installiert nur den neuen Node und lässt die bestehenden unverändert. Der Node bootet neu, der Health-Check wartet darauf.
5. Danach darfst du den `dhcp_ips`-Eintrag wieder löschen.

Hinweise:

- Control Planes immer in ungerader Zahl halten (3 oder 5), sonst verliert etcd bei einem Ausfall das Quorum.
- Eine bestehende `ip` oder `install_disk` nachträglich zu ändern installiert nicht neu. Dafür muss der Node zurückgesetzt und neu von der ISO gebootet werden.
- Einen Node entfernst du erst mit `talosctl reset` (und bei Control Planes mit `etcd remove-member`) und danach durch Löschen des Eintrags in `nodes`. Nur den Eintrag zu löschen lässt den Node weiterlaufen.

## Gateway API

Der Cluster nutzt ausschließlich Gateway API, einen Ingress-Controller gibt es nicht (`ingressController.enabled: false`). Talos lädt über ein einziges `KubeExternalManifestConfig` in der Control-Plane-Config die `standard-install.yaml` des Gateway-API-Releases (alle CRDs des Standard-Channels). Die Version steuert `gateway_api_version` (Standard `v1.6.3`, die Version, gegen die Cilium 1.20 getestet ist). Die Control Planes brauchen dafür HTTPS-Zugriff auf `github.com`. Terraform wartet nicht auf die CRDs, Kubernetes reconciled das selbst.

Genauso lädt Talos `metrics-server` (`components.yaml`) und den `kubelet-serving-cert-approver`. metrics-server prüft die Serving-Zertifikate der Kubelets. Deshalb holen sich die Kubelets ihr Zertifikat per CSR von der Cluster-CA (`KubeletConfig` mit `serverTLSBootstrap: true` in `common.yaml.tftpl`), und der Approver genehmigt diese CSRs, sofern die SANs zum Node passen. Ohne Approver bleiben die CSRs offen, dann schlagen `kubectl logs`/`exec` und metrics-server fehl.

Ein Gateway bekommt von Cilium einen Service vom Typ LoadBalancer. Auf Bare Metal braucht der eine Adressquelle, etwa Cilium LB-IPAM mit L2-Announcements. Pool und Policy gehören zu deinem Netz und sind hier nicht enthalten.

## Versionen

| Komponente | Variable | Standard |
| --- | --- | --- |
| Talos | `talos_version` | `v1.14.6` |
| Kubernetes | `kubernetes_version` | `1.37.2` |
| Cilium | `ArgoCD/Infrastructure/cilium/config.yaml` | `1.20.5` |
| Gateway API | `gateway_api_version` | `v1.6.3` |
| metrics-server | `metrics_server_version` | `v0.9.1` |
| kubelet-serving-cert-approver | `kubelet_serving_cert_approver_version` | `v0.12.1` |
| Argo CD (Chart `argo-cd`) | `ArgoCD/Infrastructure/argocd/config.yaml` | `10.18.2` (Argo CD v3.6.2) |

Der Talos-Provider ist auf `0.13.0-alpha.2` gepinnt. Diese Version bringt das Talos-SDK 1.14 mit und kennt die neuen Config-Dokumente (`UnattendedInstallConfig`, `KubeExternalManifestConfig` und weitere).

## Argo CD

`argocd.tf` installiert das Chart `argo-cd` in den Namespace `argocd`. Die Values in `ArgoCD/Infrastructure/argocd/values.yaml` enthalten die HTTPRoute und den Login über den zentralen Dex (`ArgoCD/Infrastructure/dex`) inklusive RBAC. Das mitgelieferte Dex ist deaktiviert, der lokale `admin` bleibt als Notzugang. Das Gateway wendet `cilium.tf` beim Bootstrap direkt nach Cilium an (Manifest `ArgoCD/Infrastructure/cilium/manifests/gateway.yaml`): Es heißt `cilium-gateway` (Kubernetes erlaubt keine Großbuchstaben in Namen) und liegt in `kube-system`. Es hat einen Listener `http` (Port 80) und einen Listener `https` (Port 443, TLS-Terminierung mit dem Secret `cilium-gateway-tls`), beide für Routen aus allen Namespaces. Wegen `gatewayAPI.hostNetwork` lauscht Envoy auf Port 80 und 443 jedes Nodes, also auch auf der VIP `192.168.10.100`. Fällt der Control-Plane-Node mit der VIP aus, übernimmt ein anderer die Adresse. Weitere Anwendungen hängen ihre HTTPRoutes an dieses Gateway. Ein zweites Gateway auf Port 80 würde im Host-Netzwerk mit dem ersten kollidieren.

Die Oberfläche ist unter `http://argocd.192.168.10.100.nip.io` erreichbar (`terraform output argocd_url`). nip.io ist ein öffentlicher DNS-Dienst, der die im Namen enthaltene IP zurückgibt. Einen eigenen DNS-Server oder eine Domain brauchst du dafür nicht.

**FritzBox:** Der DNS-Rebind-Schutz verwirft öffentliche DNS-Antworten mit privaten Adressen. Trage dafür eine Ausnahme ein: Heimnetz, Netzwerk, Netzwerkeinstellungen, „weitere Einstellungen“, DNS-Rebind-Schutz, Zeile `nip.io`, dann Übernehmen. Danach prüfen:

```sh
dig +short argocd.192.168.10.100.nip.io    # muss 192.168.10.100 liefern
```

Ohne Ausnahme hilft auf einzelnen Rechnern ein Eintrag in `/etc/hosts`: `192.168.10.100 argocd.192.168.10.100.nip.io`.

Anmelden mit dem Benutzer `admin`. Das Startpasswort steht im Secret `argocd-initial-admin-secret`:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
argocd login argocd.192.168.10.100.nip.io --grpc-web --plaintext --username admin
argocd account update-password --grpc-web
kubectl -n argocd delete secret argocd-initial-admin-secret   # nach dem Passwortwechsel
```

Die Verbindung ist unverschlüsseltes HTTP (`server.insecure: true`), also nur für das Heimnetz gedacht. Für HTTPS gibt es den Listener `https` am Gateway, aber beim Bootstrap noch kein Zertifikat: Das Secret `cilium-gateway-tls` fehlt, der Listener bleibt unprogrammiert und HTTP funktioniert trotzdem. Sobald Argo CD und cert-manager laufen, legst du ein `Certificate` in `kube-system` an, das das Secret `cilium-gateway-tls` erzeugt. Danach wird der HTTPS-Listener aktiv.

## Übergabe an Argo CD

Terraform ist nur für die Erstinstallation zuständig. `helm_release.cilium`, `kubectl_manifest.cilium_gateway` und `helm_release.argocd` haben `lifecycle { ignore_changes = all }`: Terraform installiert sie auf einem neuen Cluster und rührt sie danach nie wieder an. Version, Values und Gateway liest Terraform aus den Tool-Ordnern `ArgoCD/Infrastructure/cilium` und `ArgoCD/Infrastructure/argocd`. Dieselben Dateien rollt danach das ApplicationSet `infrastructure` als Apps `cilium-in-cluster` und `argocd-in-cluster` aus (Release-Namen `cilium` und `argocd`, wie bei Terraform). Es gibt also nur eine Quelle.

Änderungen an Cilium, Gateway oder Argo CD (auch Versions-Updates) laufen ab dann nur noch über Git und Argo CD. Ein `terraform apply` zeigt dafür keinen Diff.

Hubble erzeugt seine TLS-Zertifikate per Job/CronJob im Cluster (`hubble.tls.auto.method: cronJob`). Die Helm-Standardmethode würde bei jedem Rendern neue Zertifikate erzeugen, Argo CD wäre dauerhaft OutOfSync.
