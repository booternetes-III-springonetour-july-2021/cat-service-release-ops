# cat-service-ops

This repo contains the files and instructions necessary for deploying [cat-service](https://github.com/booternetes-III-springonetour-july-2021/cat-service) to Kubernetes.

## Assumptions

The configuration of the Docker registry assumes that you are working on the Booternetes cluster in GCP project `pgtm-jlong`. 
If you are, you should have access to push container images to `gcr.io/pgtm-jlong`.
If you want to work with a different registry, replace all instances of "gcr.io/pgtm-jlong" with your registry address.

## Option 1: Manual Deployment to K8s

Please refer to [deploy-manually.sh](./deploy-manually.sh).
The script will automatically build a container image and deploy it to dev and prod namespaces.

> Note: The script also includes commands to test the dev and prod deployments, and clean up at the end.
These sections are commented out. 
After running the script, you need to copy and paste them manually into the terminal.

## Option 2: Automated Deployment to K8s

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

### ArgoCD (apply deployments)

[argocd](https://argoproj.github.io/argo-cd) is a Kubernetes-native deployment server that can deploy your application to Kubernetes anytime the Kubernetes manifests are updated.

To install ArgoCD, run:
> Note: check [here](https://github.com/argoproj/argo-cd/releases) for the latest version of ArgoCD.
> You can use `grep "image: quay.io/argoproj/argocd:" tooling/argocd/install.yaml` to check the version saved to this repo.
```shell
kubectl create namespace argocd
kubectl apply -n argocd -f tooling/argocd/install.yaml
```

Make sure all pods are running and ready:
```shell
kubectl get pods -n argocd
```

ArgoCD uses a CRD called an "Application" to manage deployments to Kubernetes.
The Application checks for updates to Kubernetes manifests and applies them when changes are detected.
Hence, you need to configure an Application to poll for changes to the `cat-service-ops` repo, which contains the yaml manifests for `cat-service`.
Notice that the files in `cat-service-ops/manifests` use kustomize to define two overlays: dev and prod.
Accordingly, you will create an ArgoCD Application for dev and another for prod.

Before proceeding, the layout of the files in `cat-service-ops/manifests` requires disabling the kustomize load restrictor.
To do this with ArgoCD, run the following command.
```shell
yq eval '.data."kustomize.buildOptions" = "--load_restrictor LoadRestrictionsNone"' <(kubectl get cm argocd-cm -o yaml -n argocd) | kubectl apply -f -
````

You can now create the ArgoCD Applications.
There are several ways to do this: the ArgoCD UI, the argocd CLI, or kubectl.
In the spirit of declarative configuration and GitOps, you will use kubectl here.

Review the files in the `deploy` directory to get a sense for the ArgoCD configuration requirements.
Create the ArgoCD Application resources for both the dev and prod deployments.
```shell
kubectl apply -f deploy/argocd-app-dev.yaml
kubectl apply -f deploy/argocd-app-prod.yaml
```

You should see dev and prod namespaces created, and in each, the corresponding dev and prod deployments of all the resources declared in `cat-service-ops/manifests/overlays/dev` and `cat-service-ops/manifests/overlays/prod.`

#### Test argocd redeployment ("sync")

Check the number of app pods that are running in the prod namespace.
```shell
kubectl get pods --selector app=cat-service -n prod
```

Edit `cat-service-ops/manifests/overlays/prod/kustomization.yaml` and change the number of replicas (`count` field). 
For example, if it is set to 1, change it to 3, or vice versa.
Push the change to GitHub.

Wait a few moments and check the number of pods again. You should see that ArgoCD has automatically detected the change to the manifest and applied the changes to the cluster.

##### ArgoCD UI and CLI

You can also interact with ArgoCD using its UI or CLI.

To log in to either, you first need to retrieve the default password for the `admin` user.
> Note: You can change the password or disable auth as well (for details, see the ArgoCD documentation).
```shell
ARGOCD_PW=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo $ARGOCD_PW
```

Next, for simplicity, open a separate terminal window and port-forward to the ArgoCD server.
```shell
kubectl port-forward svc/argocd-server -n argocd 9090:80
```

You should now be able to view the ArgoCD UI at [http://localhost:9090](http://localhost:9090).
You can log in as `admin` using the password that was echoed to terminal  by `echo $ARGOCD_PW`.
Note that two Applications ayou defined earlier appear. 
They should be Synced and Healthy.
Play around in the UI to get a sense for the kind of information and options available.

ArgoCD also provides a [CLI](https://argoproj.github.io/argo-cd/getting_started/#2-download-argo-cd-cli).
After downloading the CLI, you can log in using the same username, password, and port-forwarding as you are using for the UI.
Run the following command.
```shell
argocd login localhost:9090 --insecure --username admin --password $ARGOCD_PW 
```

As an example, you can list the Applications currently defined, including status, health, and other information.
```shell
argocd app list
```

See the documentation or use `argocd --help` to explore the CLI further.
You can also refer to this section of the [docs](https://argoproj.github.io/argo-cd/getting_started/#6-create-an-application-from-a-git-repository) to see how you could define the same two Applications using either the UI or the CLI.

In your second terminal, use Ctrl+C to stop the port-forwarding.

### ArgoCD Image Updater (check for container updates)

[argocd-image-updater](https://github.com/argoproj-labs/argocd-image-updater) works in conjunction with ArgoCD to automate deployments when images on a container registry are updated.

#### TODO: Finish this section...

### Cleanup cluster
```shell
kubectl delete ns kpack
kubectl delete ns argocd
kubectl delete ns dev
kubectl delete ns prod
```
