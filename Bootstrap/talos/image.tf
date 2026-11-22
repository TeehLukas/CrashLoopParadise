# Image Factory: Schematic registrieren und daraus Installer-Image und ISO-URL ableiten.
resource "talos_image_factory_schematic" "this" {
  schematic = file("${path.module}/image/schematic.yaml")
}

data "talos_image_factory_urls" "this" {
  talos_version = var.cluster.talos_version
  schematic_id  = talos_image_factory_schematic.this.id
  platform      = "metal"
  architecture  = "amd64"
}
