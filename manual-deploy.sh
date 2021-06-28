#!/bin/bash

# Clone app
rm -rf _temp-cat-service-release
git clone https://github.com/booternetes-III-springonetour-july-2021/cat-service-release _temp-cat-service-release
cd _temp-cat-service-release

# Build an publish image
./mvnw spring-boot:build-image \
        -DskipTests \
        -Dspring-boot.build-image.imageName=gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
docker push gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
docker tag gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT gcr.io/pgtm-jlong/cat-service:latest
docker push gcr.io/pgtm-jlong/cat-service:latest

# Create config manifest
kubectl create configmap cat-service-config \
        --from-file=src/main/resources/application.properties \
        -o yaml --dry-run=client > ../manifests/base/config/configmap.yaml

cd ..

# Deploy to Kubernetes (dev namespace)
kubectl create ns dev
kustomize build --load-restrictor LoadRestrictionsNone manifests/overlays/dev/ | kubectl apply -f -

# Deploy to Kubernetes (prod namespace)
kubectl create ns prod
kustomize build --load-restrictor LoadRestrictionsNone manifests/overlays/prod/ | kubectl apply -f -

# Test the app
echo -e "\nTesting dev-cat-service"
kubectl port-forward service/dev-cat-service 8080:8080 -n dev >/dev/null 2>&1 &
k_pid=$!
sleep 5
http :8080/actuator/health
http :8080/cats/Toby
kill $k_pid
sleep 3

echo -e "\nTesting prod-cat-service"
kubectl port-forward service/prod-cat-service 8080:8080 -n prod >/dev/null 2>&1 &
k_pid=$!
sleep 5
http :8080/actuator/health
http :8080/cats/Toby
kill $k_pid
