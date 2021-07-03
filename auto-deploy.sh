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

############################################################
# Install kpack
echo -e "\nChecking for available updates for kpack"
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
kubectl apply -f $CURRENT

# Create secret for publishing to Docker registry
if [[ $(kubectl get secret regcred -n kpack --ignore-not-found) ]]; then
  echo -e "\nSecret regcred already exists"
else
  echo -e "\nCreating secret regcred from file $DOCKER_REG_CREDS"
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
echo -e "\nCreating kpack service account and builder"
kubectl apply -f "$CURRENT_BASE_DL/tooling/kpack-config/service-account.yaml"
kubectl apply -f "$CURRENT_BASE_DL/tooling/kpack-config/builder.yaml"

# Wait for builder to be ready
echo -e "\nChecking for booternetes-builder"
while [[ ! $(kubectl get bldr booternetes-builder -n kpack --ignore-not-found | grep True) ]]; do
  echo "Waiting for booternetes-builder to be ready..."
  sleep 3
done

# Apply kpack image manifest
echo -e "\nCreating kpack image"
kubectl apply -f "$CURRENT_BASE_DL/build/kpack-image.yaml"

############################################################
# Install ArgoCD
echo -e "\nChecking for available updates for argocd"
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
kubectl apply -n argocd -f $CURRENT

# Get ArgoCD admin password
# Wait for argocd admin secret to be ready
echo -e "\nChecking for argocd-initial-admin-secret"
while [[ ! $(kubectl get secret argocd-initial-admin-secret -n argocd --ignore-not-found) ]]; do
  echo "Waiting for argocd-initial-admin-secret to be ready..."
  sleep 3
done
ARGOCD_PW=$(kubectl get secret argocd-initial-admin-secret -n argocd -o jsonpath="{.data.password}" | base64 -d)
echo -e "\nArgoCD password is stored in \$ARGOCD_PW\n"

# Set kustomize load restrictor for ArgoCD
yq eval '.data."kustomize.buildOptions" = "--load_restrictor LoadRestrictionsNone"' <(kubectl get cm argocd-cm -o yaml -n argocd) | kubectl apply -f -

############################################################
# Install argocd-image-updater
echo -e "\nInstalling argocd-image-updater"

# Install argocd-image-updater
echo -e "\nChecking for available updates for argocd-image-updater"
CURRENT_FILE="tooling/argocd-image-updater/install.yaml"
CURRENT="$CURRENT_BASE_DL/$CURRENT_FILE"
LATEST_VERSION=$(curl -s https://api.github.com/repos/argoproj-labs/argocd-image-updater/releases/latest | jq -r '.tag_name')
LATEST="https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/$LATEST_VERSION/manifests/install.yaml"

DIFF=$(diff <(curl -fsLJ $CURRENT | grep "image: argoprojlabs/argocd-image-updater:" | tail -1) <(curl -fsLJ $LATEST | grep "image: argoprojlabs/argocd-image-updater:" | tail -1))

if [ "$DIFF" != "" ]
then
    printf "${RED}A new version of argocd-image-updater is available.\n${NC}"
    printf "${RED}$DIFF\n${NC}"
    printf "${RED}To install the latest version, update the following file and re-run this script.\n${NC}"
    printf "${RED}     Update: "$CURRENT_BASE/$CURRENT_FILE"\n${NC}"
    printf "${RED}     With: $LATEST\n\n${NC}"
    while true; do
    read -p "Do you wish to continue installing the OLDER version of argocd-image-updater? " yn
    case $yn in
        [Yy]* ) break;;
        [Nn]* ) exit;;
        * ) printf "${RED}Please answer yes or no.\n${NC}";;
    esac
done
fi

echo "Installing argocd-image-updater from $CURRENT"
kubectl apply -n argocd -f $CURRENT

kubectl rollout status deploy/argocd-image-updater -n argocd

# Set logging to debug (Default is info. Options are trace, debug, info, warn or error)
yq eval '.data."log.level" = "debug"' <(kubectl get cm argocd-image-updater-config -o yaml -n argocd) | kubectl apply -f -

# Create user "image-updater" in ArgoCD for argocd-image-updater and generate auth token for the new account to talk to ArgoCD API
# apiKey capability - allows generating authentication tokens for API access
yq eval '.data."accounts.image-updater" = "apiKey"' <(kubectl get cm argocd-cm -o yaml -n argocd) | kubectl apply -f -
argocd --port-forward --port-forward-namespace argocd login --username admin --password $ARGOCD_PW
IMAGE_UPDATER_ARGOCD_API_TOKEN=$(argocd --port-forward --port-forward-namespace argocd account generate-token --account image-updater --id image-updater)
###echo $IMAGE_UPDATER_ARGOCD_API_TOKEN
### LEARN MORE ABOUT ARCD USERS: https://argoproj.github.io/argo-cd/operator-manual/user-management/#create-new-user
### TO CHECK:
### kubectl get cm argocd-cm -o yaml -n argocd
### or:
### argocd --port-forward --port-forward-namespace argocd account list
### argocd --port-forward --port-forward-namespace argocd account get --account image-updater
### TO DELETE:
### argocd --port-forward --port-forward-namespace argocd account delete-token --account image-updater image-updater

# Create roles for new account
### SEE https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/#basic-built-in-roles
### SEE ALSO: https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/argocd-rbac-cm.yaml

# Add RBAC permissions to Argo CD's argocd-rbac-cm ConfigMap and Argo CD will pick them up automatically.
kubectl apply -f "$CURRENT_BASE_DL/tooling/argocd-image-updater-config/argocd-rbac-cm.yaml" -n argocd
### kubectl get cm argocd-rbac-cm -o yaml -n argocd

# Create secret from token generated above and restart the argocd-image-updater pod
kubectl create secret generic argocd-image-updater-secret \
  --from-literal argocd.token=$IMAGE_UPDATER_ARGOCD_API_TOKEN \
  --dry-run=client -o yaml | kubectl apply -f - -n argocd

kubectl rollout restart deployment argocd-image-updater -n argocd

# Create secret for argocd-image-updater to push to Git repository
if [[ $(kubectl get secret gitcred -n argocd --ignore-not-found) ]]; then
  echo -e "\nSecret gitcred already exists"
else
  echo -e "\nCreating secret gitcred from \$GIT_ACCESS_TOKEN"
  if [[ "${GIT_ACCESS_TOKEN}" == "" ]]; then
    printf "${RED}\nEnv var \$GIT_ACCESS_TOKEN is not set.\n\n${NC}"
    echo -n "Enter your GitHub access token: " && read -s GIT_ACCESS_TOKEN || { stty -echo; read GIT_ACCESS_TOKEN; stty echo; }
    export GIT_ACCESS_TOKEN
    echo
  fi
  kubectl create secret generic gitcred \
      --from-literal=username="" \
      --from-literal=password=$GIT_ACCESS_TOKEN \
      -n argocd
fi

############################################################
# Create ArgoCD Application resources
# Wait for app image to be ready
echo -e "\nChecking for cat-service image in gcr.io"
while [[ ! $(skopeo list-tags docker://gcr.io/pgtm-jlong/cat-service | grep latest) ]]; do
  echo "Waiting for docker://gcr.io/pgtm-jlong/cat-service:latest to be ready..."
  sleep 5
done

echo -e "\nCreating argocd Application resources"
kubectl apply -f "$CURRENT_BASE_DL/deploy/argocd-app-dev.yaml"
kubectl apply -f "$CURRENT_BASE_DL/deploy/argocd-app-prod.yaml"

# Wait for apps to be ready
echo -e "\nChecking status of cat-service pod in dev and prod namespaces"
while [[ ! $(kubectl get pods --selector app=cat-service -n dev | grep Running | grep "1/1") || ! $(kubectl get pods --selector app=cat-service -n prod | grep Running | grep "1/1") ]]; do
  echo "Waiting for cat-service to be ready..."
  sleep 5
done

# Test the app
echo -e "\nTesting dev-cat-service"
kubectl port-forward service/dev-cat-service 8080:8080 -n dev >/dev/null 2>&1 &
pid_dev=$!
sleep 5
http :8080/actuator/health
http :8080/cats/Toby
kill $pid_dev
sleep 3

echo -e "\nTesting prod-cat-service"
kubectl port-forward service/prod-cat-service 8081:8080 -n prod >/dev/null 2>&1 &
pid_prod=$!
sleep 5
http :8081/actuator/health
http :8081/cats/Toby
kill $pid_prod

#kill $pid_dev; sleep 3; kubectl port-forward service/dev-cat-service 8080:8080 -n dev >/dev/null 2>&1 &
#pid_dev=$!
#kill $pid_prod; sleep 3; kubectl port-forward service/prod-cat-service 8081:8080 -n prod >/dev/null 2>&1 &
#pid_prod=$!
#sleep 5
