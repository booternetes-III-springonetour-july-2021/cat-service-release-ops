# cat-service-ops

This repo contains the files and instructions necessary for deploying [cat-service](https://github.com/booternetes-III-springonetour-july-2021/cat-service) to Kubernetes.

### Assumptions

The configuration of the Docker registry assumes that you are working on the Booternetes cluster in GCP project pgtm-jlong. 
If you are, you should have access to push container images to gcr.io/pgtm-jlong.
If you want to work with a different registry, replace all instances of "gcr.io/pgtm-jlong" with your registry address.

### Option : Manual Deployment to K8s

Please refer to [deploy-to-k8s.sh](./deploy-to-k8s.sh).

### Option 2: Automated Deployment to K8s

This section will guide you through automating the application build and deployment using kpack and ArgoCD.

[kpack](https://github.com/pivotal/kpack) is a Kubernetes-native build server for building container images in an automated way, at scale, and keeping the images updated with any OS and runtime patches/releases.

[argocd](https://argoproj.github.io/argo-cd) is a Kubernetes-native deployment server that can deploy your application to Kubernetes anytime the Kubernetes manifests are updated.

[argocd-image-updater](https://github.com/argoproj-labs/argocd-image-updater) works in conjunction with ArgoCD to automate deployments when images on a container registry are updated.

#### kpack (build images)

To install kpack, run:
> Note: check [here](https://github.com/pivotal/kpack/releases) for the latest version of kpack.
```
kubectl apply  --filename https://github.com/pivotal/kpack/releases/download/v0.2.2/release-0.2.2.yaml
```

kpack will need to authenticate with the Docker registry in order to push images.

If you are using the shared Booternetes server, log into GCP and download the .json credentials file for the service account `kpack-push-image@pgtm-jlong.iam.gserviceaccount.com`.
If necessary, update the path and filename specified below.
Then run the following command:
```shell
kubectl create secret docker-registry regcred \
        --docker-server "https://gcr.io" \
        --docker-username _json_key \
        --docker-email kpack-push-image@pgtm-jlong.iam.gserviceaccount.com \
        --docker-password="$(cat ~/Downloads/pgtm-jlong-6a94c0f57048.json)"
```

> Note: If you are using your own registry, make sure to use your own registry information to create the secret, but keep the name as "regcred" since that is what will be specified in the Service Account configuration.
If you are using Docker Hub, for example, and are logged in to docker on your local machine, you can run the following command:
```shell
# kubectl create secret generic regcred \
#         --from-file=.dockerconfigjson=/root/.docker/config.json \
#         --type=kubernetes.io/dockerconfigjson
```

Next, create the Service Account that will use this Secret.
Also, create the Builder to use. A Builder comprises a Stack (base image) and a Store (buildpacks).
To create the Service Account and Builder, apply the kpack manifests included in this repo.
``` 
kubectl apply -f kpack/service-account.yaml
kubectl apply -f kpack/builder.yaml
```

kpack will create a Builder image called 'paketo-builder' and push it to the Docker registry.
Check the status using the following command:
```shell
k get builders
```

If the image has been successfully built, the output will look comething like this:
``` 
NAME             LATESTIMAGE                                                                                                READY
paketo-builder   gcr.io/pgtm-jlong/paketo-builder@sha256:749dd998f88399807db841ae9d247397fd4b9f331014bb1b2293b2d3cca03190   True
```

You can use `k describe builders` to troubleshoot if the image has not been created.

You can also check the [GCR Console](https://console.cloud.google.com/gcr/images/pgtm-jlong/GLOBAL/paketo-builder) or using the following command to verify that the image has been pushed.
```shell
skopeo list-tags docker://gcr.io/pgtm-jlong/paketo-builder
```

Now that you have a Builder image and have granted kpack rights to the Docker registry, you can automate builds for the `cat-service` application.
Apply the kpack image YAML file included in this repo.
This will trigger kpack to build an image from the app repo.
``` 
kubectl apply -f image/image.yaml
```

You can use `kubectl get images` to see the image you just created, and `kubectl get builds` or `kubectl describe build <build-name>` to track the status or troubleshoot a particular build. Each build also creates a corresponding Pod that you can examine. The output from `kubectl describe pod <pod-name>` should show the buildpacks lifecycle stages being executed (detect, analyze, restore, build, export).

You can also download the [kpack logs CLI](https://github.com/pivotal/kpack/releases/) to facilitate troubleshooting.

Once the build is complete, you should see the cat-service image has been published to gcr.io. The `latest` tag will be assigned by default, as well as a tag indicating the build number, date, and a random id.
```shell
skopeo list-tags docker://gcr.io/pgtm-jlong/cat-service
```

Push any change to the `cat-service` app repo in order to create a new commit. Check for a new build resource in Kubernetes and a new image in the container registry to verify that kpack detected the new commit and automatically kicked off a new build.

#### ArgoCD (apply deployments)

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

<WIP>

#### Cleanup:
```shell
kubectl delete -f https://github.com/pivotal/kpack/releases/download/v0.2.2/release-0.2.2.yaml
kubectl delete -f image/image.yaml
kubectl delete -f kpack/builder.yaml
kubectl delete -f kpack/service-account.yaml
kubectl delete secret regcred
```


