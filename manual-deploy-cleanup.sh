# Cleanup

kustomize build --load-restrictor LoadRestrictionsNone manifests/overlays/dev/ | kubectl delete -f -
kubectl delete ns dev

kustomize build --load-restrictor LoadRestrictionsNone manifests/overlays/prod/ | kubectl delete -f -
kubectl delete ns prod

docker rmi -f gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
docker rmi -f gcr.io/pgtm-jlong/cat-service:latest

##skopeo delete docker://gcr.io/pgtm-jlong/cat-service:0.0.1-SNAPSHOT
##skopeo delete docker://gcr.io/pgtm-jlong/cat-service:latest