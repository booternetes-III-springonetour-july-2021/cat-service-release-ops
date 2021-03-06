#!/usr/local/bin/bash

CURRENT_BASE_DL="https://raw.githubusercontent.com/booternetes-III-springonetour-july-2021/cat-service-release-ops/main"

############################################################
# Uninstall argocd-image-updater
echo "Uninstalling argocd-image-updater"

kubectl delete secret gitcred -n argocd
#argocd --port-forward --port-forward-namespace argocd account delete-token --account image-updater image-updater
kubectl delete -n argocd -f "$CURRENT_BASE_DL/tooling/argocd-image-updater-config/argocd-rbac-cm.yaml"
kubectl delete -n argocd -f "$CURRENT_BASE_DL/tooling/argocd-image-updater/install.yaml"

############################################################
# Uninstall ArgoCD
echo "Uninstalling argocd"

# Delete ArgoCD Application resources
kubectl delete -f "$CURRENT_BASE_DL/deploy/argocd-app-dev.yaml"
kubectl delete -f "$CURRENT_BASE_DL/deploy/argocd-app-prod.yaml"

# Delete ArgoCD
kubectl delete -n argocd -f "$CURRENT_BASE_DL/tooling/argocd/install.yaml"
kubectl delete namespace argocd

############################################################
# Uninstall kpack
echo "Uninstalling kpack"

# Delete kpack image manifest, service account, builder, and Docker registry secret
kubectl delete -f "$CURRENT_BASE_DL/build/kpack-image.yaml"
kubectl delete -f "$CURRENT_BASE_DL/tooling/kpack-config/service-account.yaml"
kubectl delete -f "$CURRENT_BASE_DL/tooling/kpack-config/builder.yaml"
kubectl delete secret regcred -n kpack

# Delete kpack
kubectl delete -f "$CURRENT_BASE_DL/tooling/kpack/release.yaml"

############################################################
# Delete app
echo "Deleting app (dev and prod)"

kubectl delete namespace dev
kubectl delete namespace prod