#!/usr/local/bin/bash

RED='\033[0;31m'
NC='\033[0m' # No Color
# To print in red:
# printf "${RED}hello\n${NC}"

CURRENT_BASE="https://github.com/booternetes-III-springonetour-july-2021/cat-service-release-ops/blob/main"
CURRENT_BASE_DL="https://raw.githubusercontent.com/booternetes-III-springonetour-july-2021/cat-service-release-ops/main"
DOCKER_REG_CREDS=~/Downloads/pgtm-jlong-6a94c0f57048.json

#CURRENT_BASE="https://github.com/booternetes-III-springonetour-july-2021/cat-service-release-ops/blob/30aeac949ebf0b9876954cd1a15a8365fba264e8"
#CURRENT_BASE_DL="https://raw.githubusercontent.com/booternetes-III-springonetour-july-2021/cat-service-release-ops/30aeac949ebf0b9876954cd1a15a8365fba264e8"

# Install kpack
echo "Checking for available updates for kpack"
CURRENT_FILE="tooling/kpack/release.yaml"
CURRENT="$CURRENT_BASE_DL/$CURRENT_FILE"
LATEST=$(curl -s https://api.github.com/repos/pivotal/kpack/releases/latest | jq -r '.assets[].browser_download_url | select(test("release-"))')
DIFF=$(diff <(curl -fsLJ $CURRENT | grep "version:" | tail -1) <(curl -fsLJ $LATEST | grep "version:" | tail -1))

if [ "$DIFF" != "" ]
then
    printf "${RED}A new version of kpack is available.\n${NC}"
    printf "${RED}$DIFF\n${NC}"
    printf "${RED}To install the latest version, update the following file and re-run this script.\n${NC}"
    printf "${RED}     Update: "$CURRENT_BASE/$CURRENT_FILE"\n${NC}"
    printf "${RED}     With: $LATEST\n\n${NC}"
    while true; do
    read -p "Do you wish to continue installing the OLDER version of kpack? " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit;;
        * ) printf "${RED}Please answer yes or no.\n${NC}";;
    esac
done
fi

echo "Installing kpack from $CURRENT"
curl -fsLJ $CURRENT | kubectl apply -f -

# Create secret for publishing to Docker registry
if [[ $(kubectl get secret regcred -n kpack --ignore-not-found) ]]; then
  echo "Secret regcred already exists"
else
  echo "Creating secret regcred from file $DOCKER_REG_CREDS"
  if [ -f $DOCKER_REG_CREDS ]; then
  kubectl create secret docker-registry regcred \
        --docker-server "https://gcr.io" \
        --docker-username _json_key \
        --docker-email kpack-push-image@pgtm-jlong.iam.gserviceaccount.com \
        --docker-password="$(cat $DOCKER_REG_CREDS)" \
        -n kpack
  else
    printf "${RED}File $DOCKER_REG_CREDS does not exist.\n${NC}"
    exit
  fi
fi

# Apply kpack service account and builder manifests
kubectl apply -f "$CURRENT_BASE_DL/tooling/kpack-config/service-account.yaml"
kubectl apply -f "$CURRENT_BASE_DL/tooling/kpack-config/builder.yaml"

# Apply kpack image manifest
kubectl apply -f "$CURRENT_BASE_DL/build/kpack-image.yaml"

# Install ArgoCD
echo "Checking for available updates for argocd"
CURRENT_FILE="tooling/argocd/install.yaml"
CURRENT="$CURRENT_BASE_DL/$CURRENT_FILE"
LATEST_VERSION=$(curl -s https://api.github.com/repos/argoproj/argo-cd/releases/latest | jq -r '.tag_name')
LATEST="https://raw.githubusercontent.com/argoproj/argo-cd/$LATEST_VERSION/manifests/install.yaml"

DIFF=$(diff <(curl -fsLJ $CURRENT | grep "image: quay.io/argoproj/argocd:" | tail -1) <(curl -fsLJ $LATEST | grep "image: quay.io/argoproj/argocd:" | tail -1))

if [ "$DIFF" != "" ]
then
    printf "${RED}A new version of argocd is available.\n${NC}"
    printf "${RED}$DIFF\n${NC}"
    printf "${RED}To install the latest version, update the following file and re-run this script.\n${NC}"
    printf "${RED}     Update: "$CURRENT_BASE/$CURRENT_FILE"\n${NC}"
    printf "${RED}     With: $LATEST\n\n${NC}"
    while true; do
    read -p "Do you wish to continue installing the OLDER version of argocd? " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit;;
        * ) printf "${RED}Please answer yes or no.\n${NC}";;
    esac
done
fi

echo "Installing argocd from $CURRENT"
kubectl create namespace argocd
curl -fsLJ $CURRENT | kubectl apply -n argocd -f -

# Set kustomize load restrictor for ArgoCD
yq eval '.data."kustomize.buildOptions" = "--load_restrictor LoadRestrictionsNone"' <(kubectl get cm argocd-cm -o yaml -n argocd) | kubectl apply -f -

# Create ArgoCD Application resources
kubectl apply -f "$CURRENT_BASE_DL/deploy/argocd-app-dev.yaml"
kubectl apply -f "$CURRENT_BASE_DL/deploy/argocd-app-prod.yaml"

# Get ArgoCD admin password
ARGOCD_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD password is stored in \$ARGOCD_PW"
