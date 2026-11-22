# Rendert die manuellen Argo-CD-Bootstrap-Manifeste.
#
# Wird ausschließlich über die Taskfile im Repo-Root ausgeführt:  task bootstrap
#
# Ablauf danach: Application "appsets" -> ArgoCD/AppSets/ (infrastructure, clusters)
import manifests

# --- Eingaben (-D key=value) -------------------------------------------------
_repo = option("repo")
_revision = option("revision") or "main"
_root = option("root_path") or "ArgoCD"
_infrastructure_path = option("infrastructure_path") or "${_root}/Infrastructure"
_clusters_path = option("clusters_path") or "${_root}/Clusters"
_appsets_path = option("appsets_path") or "${_root}/AppSets"
_cluster_name = option("cluster_name") or "in-cluster"
_cluster_server = option("cluster_server") or "https://kubernetes.default.svc"
_onepassword_token = option("onepassword_token")
# Teilmenge rendern: secrets | repo | root | full (Standard)
_part = option("part") or "full"

assert _repo or _part == "secrets", "repo fehlt (BOOTSTRAP_REPO)"
assert _onepassword_token or _part in ["repo", "root"], "onepassword_token fehlt (OP_SERVICE_ACCOUNT_TOKEN)"

# Cluster-Secret des Management-Clusters. Repo, Branch und Pfade lesen alle ApplicationSets von hier.
_cluster_secret = {
    apiVersion = "v1"
    kind = "Secret"
    metadata = {
        name = "cluster-in-cluster"
        namespace = "argocd"
        labels = {
            "argocd.argoproj.io/secret-type" = "cluster"
            infrastructure = "true"  # rollt alle Tools unter infrastructure-path aus
            management = "true"  # verwaltet die Cluster-Secrets aus clusters-path
        }
        annotations = {
            repo = _repo
            revision = _revision
            "infrastructure-path" = _infrastructure_path
            "clusters-path" = _clusters_path
        }
    }
    type = "Opaque"
    stringData = {
        name = _cluster_name
        server = _cluster_server
        config = '{"tlsClientConfig": {"insecure": false}}'
    }
}

# Initiale Application, zeigt auf die ApplicationSets im Git.
_appsets = {
    apiVersion = "argoproj.io/v1alpha1"
    kind = "Application"
    metadata = {name = "appsets", namespace = "argocd"}
    spec = {
        project = "default"
        destination = {server = _cluster_server, namespace = "argocd"}
        source = {
            repoURL = _repo
            targetRevision = _revision
            path = _appsets_path
        }
        syncPolicy.automated = {prune = True, selfHeal = True}
    }
}

# Vorbedingung für den 1Password-ClusterSecretStore (external-secrets/manifests).
_namespace = {
    apiVersion = "v1"
    kind = "Namespace"
    metadata.name = "external-secrets"
}

_onepassword_secret = {
    apiVersion = "v1"
    kind = "Secret"
    metadata = {name = "onepassword-token", namespace = "external-secrets"}
    type = "Opaque"
    stringData.token = _onepassword_token
}

_parts = {
    # 1) Secret-Store-Zugang für External Secrets
    secrets = [_namespace, _onepassword_secret]
    # 2) Secret mit Repo/Git-Infos (Cluster-Secret)
    repo = [_cluster_secret]
    # 3) Root-Application auf ArgoCD/AppSets
    root = [_appsets]
    full = [_namespace, _onepassword_secret, _cluster_secret, _appsets]
}

manifests.yaml_stream(_parts[_part])
