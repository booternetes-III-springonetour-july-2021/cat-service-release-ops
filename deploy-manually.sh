# Clone app and build image
rm -rf temp-cat-service
git clone https://github.com/booternetes-III-springonetour-july-2021/cat-service temp-cat-service
cd temp-cat-service
./mvnw spring-boot:build-image \
        -DskipTests \
        -Dspring-boot.build-image.imageName=gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
docker push gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
kubectl create configmap cat-service-config \
        --from-file=src/main/resources/application.properties \
        -o yaml --dry-run=client > ../manifests/base/config/configmap.yaml
cd ..

# Deploy to Kubernetes (dev namespace)
kubectl create ns dev
kustomize build --load-restrictor LoadRestrictionsNone manifests/overlays/dev/ | kubectl apply -f -

# Test the dev app
#kubectl port-forward service/dev-cat-service 8080:8080 -n dev
#http :8080/cats/Toby
#http :8080/actuator/health

# Deploy to Kubernetes (prod namespace)
kubectl create ns prod
kustomize build --load-restrictor LoadRestrictionsNone manifests/overlays/prod/ | kubectl apply -f -

# Test the prod app
#kubectl port-forward service/prod-cat-service 8081:8080 -n prod
#http :8081/cats/Toby
#http :8081/actuator/health

# Cleanup
kubectl delete ns dev
kubectl delete ns prod
docker rmi -f gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
#skopeo delete docker://gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
