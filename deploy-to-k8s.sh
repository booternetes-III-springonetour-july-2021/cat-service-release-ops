# Clone app and build image
git clone https://github.com/booternetes-III-springonetour-july-2021/cat-service temp-cat-service
cd temp-cat-service
./mvnw spring-boot:build-image \
        -DskipTests \
        -Dspring-boot.build-image.imageName=gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
docker push gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
kubectl create configmap cat-service-config \
        --from-file=src/main/resources/application.properties \
        -o yaml --dry-run=client > ../ops/base/configmap.yaml
cd ..
rm -rf temp-cat-service

# Deploy to Kubernetes (dev namespace)
kubectl create ns dev
kubectl apply -f db/postgres.yaml -n dev
kustomize build --load-restrictor LoadRestrictionsNone ops/overlays/dev/ | kubectl apply -f -

# To test
#kubectl port-forward service/dev-cat-service 8080:8080
#http :8080/cats/Toby
#http :8080/actuator/health

# Deploy to Kubernetes (prod namespace)
#kubectl create ns prod
#kubectl apply -f db/postgres.yaml -n prod
#kustomize build --load-restrictor LoadRestrictionsNone ops/overlays/prod/ | kubectl apply -f -

# To test
#kubectl port-forward service/prod-cat-service 8081:8080
#http :8081/cats/Toby
#http :8081/actuator/health


# Cleanup
#kustomize build --load-restrictor LoadRestrictionsNone ops/overlays/dev/ | kubectl delete -f -
#kubectl delete -f db/postgres.yaml -n dev
#kubectl delete ns dev
#
#kustomize build --load-restrictor LoadRestrictionsNone ops/overlays/prod/ | kubectl delete -f -
#kubectl delete -f db/postgres.yaml -n prod
#kubectl delete ns prod
#
#docker rmi -f gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
##skopeo delete docker://gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
