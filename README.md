# cat-service-ops

This repo contains the files and instructions necessary for deploying [cat-service](https://github.com/booternetes-III-springonetour-july-2021/cat-service) to Kubernetes.

### Assumptions

The configuration of the Docker registry assumes that you are working on the Booternetes cluster in GCP project `pgtm-jlong`. 
If you are, you should have access to push container images to `gcr.io/pgtm-jlong`.
If you want to work with a different registry, replace all instances of "gcr.io/pgtm-jlong" with your registry address.

### Option : Manual Deployment to K8s

Please refer to [deploy-manually.sh](./deploy-manually.sh).
The script will automatically build a container image and deploy it to dev and prod namespaces.

> Note: The script also includes commands to test the dev and prod deployments, and clean up at the end.
These sections are commented out. 
After running the script, you need to copy and paste them manually into the terminal.

### Option 2: Automated Deployment to K8s

This section will guide you through automating the application build and deployment using kpack and ArgoCD.

[kpack](https://github.com/pivotal/kpack) is a Kubernetes-native build server for building container images in an automated way, at scale, and keeping the images updated with any OS and runtime patches/releases.

[argocd](https://argoproj.github.io/argo-cd) is a Kubernetes-native deployment server that can deploy your application to Kubernetes anytime the Kubernetes manifests are updated.

[argocd-image-updater](https://github.com/argoproj-labs/argocd-image-updater) works in conjunction with ArgoCD to automate deployments when images on a container registry are updated.

#### kpack (build images)

To install kpack, run:
> Note: check [here](https://github.com/pivotal/kpack/releases) for the latest version of kpack.
> You can use `grep "version:" tooling/kpack/release.yaml` to check the version saved to this repo.
```
kubectl apply -f tooling/kpack/release.yaml
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
        --docker-password="$(cat ~/Downloads/pgtm-jlong-6a94c0f57048.json)" \
        -n kpack
```

> Note: If you are using your own registry, make sure to use your own registry information to create the secret, but keep the name as "regcred" since that is what will be specified in the Service Account configuration.
> If you are using Docker Hub, for example, and are logged in to docker on your local machine, you can run the following command:
```shell
# kubectl create secret generic regcred \
#         --from-file=.dockerconfigjson=/root/.docker/config.json \
#         --type=kubernetes.io/dockerconfigjson \
#         -n kpack
```

Next, create the Service Account that will use this Secret.
Also, create the Builder to use. A Builder comprises a Stack (base image) and a Store (buildpacks).
To create the Service Account and Builder, apply the kpack manifests included in this repo.
``` 
kubectl apply -f tooling/kpack-config/service-account.yaml
kubectl apply -f tooling/kpack-config/builder.yaml
```

kpack will create a Builder image called 'booternetes-builder' and push it to the Docker registry.
Check the status of the resources you just created using the following command:
```shell
kubectl get bldr -n kpack
```

If the image has been successfully built, the output will look something like this:
``` 
NAME             LATESTIMAGE                                                                                                READY
booternetes-builder   gcr.io/pgtm-jlong/booternetes-builder@sha256:749dd998f88399807db841ae9d247397fd4b9f331014bb1b2293b2d3cca03190   True
```

You can use `kubectl describe bldr booternetes-builder -n kpack` to get more info about the status (or troubleshoot) if your output does not show a ready image.

Once the image is created, you can validate that it has been published by checking the [GCR Console](https://console.cloud.google.com/gcr/images/pgtm-jlong/GLOBAL/booternetes-builder) or using the following command.
```shell
skopeo list-tags docker://gcr.io/pgtm-jlong/booternetes-builder
```

Now that you have a Builder image and have granted kpack rights to the Docker registry, you can automate builds for the `cat-service` application.
Apply the kpack image YAML file included in this repo.
This will trigger kpack to build an image from the app repo.
``` 
kubectl apply -f build/kpack-image.yaml
```

You can use `kubectl get images` to see the image you just created.
Once the build is complete, you should see the `READY=true` and `LATESTIMAGE=<image reference>`, indicating that the cat-service image has been published to gcr.io. 
The `latest` tag will be assigned by default, as well as a tag indicating the build number, date, and a random id.
You can also use the `skopeo` CLI to check the container registry.
```shell
skopeo list-tags docker://gcr.io/pgtm-jlong/cat-service
```

> Note: The build may take a few minutes.
While you are waiting, you can use `kubectl get builds` or `kubectl get pods` to see the build and pod that are created for a particular build. 
You can also use `kubectl describe build <build-name>` to track the status.
When the build is done you will see all of the lifecycle stages listed in the output, as follows:
```
  Steps Completed:
    prepare
    detect
    analyze
    restore
    build
    export
Events:  <none>
```

#### Test kpack auto-rebuild

Push any change to the `cat-service` app repo. 
For example, you can make a change to `cat-service/bump` simply to create a new git commit.
After a few seconds, run `kubectl get builds` to validate that kpack has kicked off a new build. Check the container repo to confirm that it has also published a new container.

#### Cleanup cluster
```shell
kubectl delete ns kpack
kubectl delete ns dev
kubectl delete ns prod
```