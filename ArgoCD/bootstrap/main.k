# Rendert die manuellen Argo-CD-Bootstrap-Manifeste. Aufruf nur über die Taskfile im Repo-Root:  task bootstrap
#
# 1) Namespace + 1Password-Token für External Secrets
# 2) Repository-Secret für Argo CD
# 3) Root-Application -> <appsets_path> (ApplicationSets und Apps, u.a. "clusters")
#
# Alles Weitere (Cluster-Secrets mit Labels/Pfaden) liegt in Git unter ArgoCD/Clusters.
import manifests

_repo = option("repo")
_appsets_path = option("appsets_path") or "ArgoCD/AppSets"
_revision = option("revision") or "main"
_onepassword_token = option("onepassword_token")

assert _repo, "repo fehlt"
assert _onepassword_token, "onepassword_token fehlt"

_namespace = {
    apiVersion = "v1"
    kind = "Namespace"
    metadata.name = "external-secrets"
}

# Zugang für den ClusterSecretStore (Infrastructure/external-secrets/manifests).
_onepassword_secret = {
    apiVersion = "v1"
    kind = "Secret"
    metadata = {name = "onepassword-token", namespace = "external-secrets"}
    type = "Opaque"
    stringData.token = _onepassword_token
}

_repo_secret = {
    apiVersion = "v1"
    kind = "Secret"
    metadata = {
        name = "repo-bootstrap"
        namespace = "argocd"
        labels = {"argocd.argoproj.io/secret-type" = "repository"}
    }
    type = "Opaque"
    stringData = {
        type = "git"
        url = _repo
    }
}

_root = {
    apiVersion = "argoproj.io/v1alpha1"
    kind = "Application"
    metadata = {name = "root", namespace = "argocd"}
    spec = {
        project = "default"
        destination = {server = "https://kubernetes.default.svc", namespace = "argocd"}
        source = {
            repoURL = _repo
            targetRevision = _revision
            path = _appsets_path
        }
        syncPolicy.automated = {prune = True, selfHeal = True}
    }
}

# Reihenfolge = Apply-Reihenfolge
manifests.yaml_stream([_namespace, _onepassword_secret, _repo_secret, _root])
