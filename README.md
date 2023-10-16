# README

Commands and config file for [Getting Started with Wasm, Docker, and Kubernetes](https://www.dockercon.com/2023/session/1736607/getting-started-with-wasm-docker-and-kubernetes) at DockerCon 2023.

The workshop is divided into the following sections:
1. [Pre-requisites](https://github.com/nigelpoulton/dockercon2023-wasm-lab/tree/main#1-pre-requisites)
2. [Build and test the app](https://github.com/nigelpoulton/dockercon2023-wasm-lab/tree/main#2-build-and-test-the-app)
3. [Package as OCI container and run on Docker Desktop](https://github.com/nigelpoulton/dockercon2023-wasm-lab/tree/main#3-package-as-oci-container-and-run-on-docker-desktop)
4. [Push to Docker Hub](https://github.com/nigelpoulton/dockercon2023-wasm-lab/tree/main#4-push-to-docker-hub)
5. [Build k3d Kubernetes cluster](https://github.com/nigelpoulton/dockercon2023-wasm-lab/tree/main#5-build-k3d-kubernetes-cluster)
6. [Configure Kubernetes for Wasm](https://github.com/nigelpoulton/dockercon2023-wasm-lab/tree/main#6-configure-kubernetes-for-wasm)
7. [Deploy Wasm app to Kubernetes and Test](https://github.com/nigelpoulton/dockercon2023-wasm-lab/tree/main#7-deploy-wasm-app-to-kubernetes-and-test)
8. [Verify Kubernetes Wasm config](https://github.com/nigelpoulton/dockercon2023-wasm-lab/tree/main#8-verify-kubernetes-wasm-config)

## 1. Pre-requisites

To complete the lab, you'll need all of the following:

- Docker Desktop 4.23+ with the containerd image store and Wasm features enabled
- Rust (preferably 1.72 or later) with the wasm32-wasi target added (`rustup target add wasm32-wasi`)
- kubectl
- k3d
    - k3d version v5.6.0 or later
    - k3s version v1.27.4-k3s1 or later
- A Docker Hub account
- Fermyon spin

## 2. Build and test the app

Create a new spin app.

```
spin new
```

Choose *http-rust*, name the app _dockercon_, and set the following options:

```
HTTP base: /
HTTP path: /yo
```

Change into the `dockercon` directory and inspect the files created by the `spin new` command.

```
cd dockercon
tree
.
├── Cargo.toml
├── spin.toml
└── src
    └── lib.rs
```

Edit the app file (lib.rs) and change the last line of the file as follows.

```
vim src/lib.rs
<Snip>
        .body(Some("Yo, DockerCon!!!".into()))?)
```

Save your changes and run a `spin build` to build the app as a Wasm app.

```
spin build
```

This command runs a `cargo build --target wasm32-wasi --release` behind the scenes to create a Wasm binary.

If you run another `tree` command, you'll see the artefacts created by the build. Notice the `dockercon.wasm` file, this is the compiled Wasm app.

Test it works with `spin up`.

```
spin up

Serving http://127.0.0.1:3000
Available Routes:
  dockercon: http://127.0.0.1:3000/yo
```

Point a browser to `http://127.0.0.1:3000/yo` or run the following curl command to check it works.

```
curl localhost:3000/yo
Yo, DockerCon!!!
```

At this point, the app is built and working. It's time to containerize it.

## 3. Package as OCI container and run on Docker Desktop

You should be in the `dockercon` directory.

Create a new file called `Dockerfile` with the following contents.

```
FROM scratch
COPY /target/wasm32-wasi/release/dockercon.wasm .
COPY spin.toml .
```

Edit the `spin.toml` file so the `source` field is as follows.

```
source = "dockercon.wasm"
```

Run the following command to build the app into an OCI image. Be sure to change the last line to use your Docker Hub ID instead of mine.

```
docker buildx build \
  --platform wasi/wasm \
  --provenance=false \
  -t nigelpoulton/docker-wasm:spin-0.1 .
```

Verify the image was built.

```
docker images
REPOSITORY                  TAG        IMAGE ID       CREATED      SIZE
nigelpoulton/docker-wasm    spin-0.1   b48c9dd9201c   1 min ago    556kB
```

Test it runs on your local Docker Desktop.

```
docker run -d \
  --runtime=io.containerd.spin.v1 \
  --platform=wasi/wasm \
  -p 3000:80 \
  nigelpoulton/docker-wasm:spin-0.1 /
```

Check the container is running and curl its `/yo` endpoint on port `3000`.

```
docker ps | grep spin
CONTAINER ID   IMAGE                   COMMAND    CREATED       STATUS      PORTS
4b339bd4e436   docker-wasm:spin-0.1    "/"        9 secs ago    Up 9 secs   0.0.0.0:3000->80/tcp

curl localhost:3000/yo
Yo DockerCon!!!
```

It works. The app is now packaged as an OCI container and ready to be pushed to Docker Hub or another OCI registry.

## 4. Push to Docker Hub

Run the following command to push the image to Docker Hub or another registry. Remember, your image will have a different tag with your own Docker Hub ID.

```
docker push nigelpoulton/docker-wasm:spin-0.1
```

Check Docker Hub to ensure the image uploaded correctly.

With the app built, containerized, and uploaded to a registry, it's time to build a Kubernetes cluster.

## 5. Build k3d Kubernetes cluster

Run the following command to create a Kubernetes cluster with one control plane node, two workers, and a load-balancer mapping. You'll need Docker Desktop running and k3d installed.

Create a cluster and test it

```
k3d cluster create wasm \
      --image ghcr.io/deislabs/containerd-wasm-shims/examples/k3d:v0.9.1 \
      -p "8081:80@loadbalancer" --agents 2

kubectl get nodes
NAME                STATUS   ROLES                  AGE     VERSION
k3d-wasm-server-0   Ready    control-plane,master   7h41m   v1.27.4+k3s1
k3d-wasm-agent-0    Ready    <none>                 7h41m   v1.27.4+k3s1
k3d-wasm-agent-1    Ready    <none>                 7h41m   v1.27.4+k3s1
```

## 6. Configure Kubernetes for Wasm

Exec onto node 1 and list the installed Wasm shims.

```
docker exec -it k3d-wasm-agent-1 ash

ls /bin | grep shim
containerd-shim-lunatic-v1
containerd-shim-runc-v2
containerd-shim-slight-v1
containerd-shim-spin-v1
containerd-shim-wws-v1
```

Check that containerd is running.

```
ps
PID   USER     COMMAND
<Snip>
  103 0        containerd
```

Check that the Wasm shims are registered in the containerd config file.

```
cat /var/lib/rancher/k3s/agent/etc/containerd/config.toml

<Snip>
[plugins.cri.containerd.runtimes.spin]
  runtime_type = "io.containerd.spin.v1"

[plugins.cri.containerd.runtimes.slight]
  runtime_type = "io.containerd.slight.v1"

[plugins.cri.containerd.runtimes.wws]
  runtime_type = "io.containerd.wws.v1"

[plugins.cri.containerd.runtimes.lunatic]
  runtime_type = "io.containerd.lunatic.v1"
```

Type `exit` to leave the container.

Add the `wasm=yes` label to node 1.

```
kubectl label nodes k3d-wasm-agent-1 wasm=yes
```

Verify the label was correctly allplied.

```
kubectl get nodes --show-labels | grep wasm=yes

NAME                STATUS   ROLES     ...  LABELS
k3d-wasm-agent-0    Ready    <none>    ...  beta.kubernetes..., wasm=yes
```

## 7. Deploy Wasm app to Kubernetes and Test

Check for existing RuntimeClasses.

```
kubectl get runtimeclass
```

Run the following command to create a new RuntimeClass called `rc-spin` that calls the `spin` handler and targets nodes with the `spin=yes` label.

```
kubectl apply -f - <<EOF
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
    name: rc-spin
handler: spin
scheduling:
  nodeSelector:
    wasm: "yes"
EOF
```

Check it installed correctly.

```
kubectl get runtimeclass
NAME      HANDLER   AGE
rc-spin   spin      1m
```

Create a new file called **app.yml** and copy in the following content.

```
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wasm-spin
spec:
  replicas: 3
  selector:
    matchLabels:
      app: wasm-spin
  template:
    metadata:
      labels:
        app: wasm-spin
    spec:
      runtimeClassName: rc-spin
      containers:
        - name: testwasm
          image: nigelpoulton/docker-wasm:spin-0.1
          command: ["/"]
---
apiVersion: v1
kind: Service
metadata:
  name: wasm-spin
spec:
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
  selector:
    app: wasm-spin
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wasm-spin
  annotations:
    ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: traefik
  rules:
    - http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: wasm-spin
                port:
                  number: 80
```

Deploy it and check it with the following commands.

```
kubectl apply -f app.yml
deployment.apps/wasm-spin configured
service/wasm-spin configured
ingress.networking.k8s.io/wasm-spin configured

kubectl get deploy
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
wasm-spin   3/3     3            3           3m
```

Check that the three replicas are all scheduled to node 1 with the Wasm runtimes.

```
kubectl get pods -o wide
NAME                         READY   STATUS    NODE               ...
wasm-spin-5f6fccc557-5jzx6   1/1     Running   k3d-wasm-agent-1   ...
wasm-spin-5f6fccc557-c2tq7   1/1     Running   k3d-wasm-agent-1   ...
wasm-spin-5f6fccc557-ft6nz   1/1     Running   k3d-wasm-agent-1   ...
```

Curl the app.

```
curl http://0.0.0.0:8081/yo
Hello, DockerCon!
```

## 8. Verify Kubernetes Wasm config

Exec a command on node 1 and check the spin processes.

```
docker exec -it k3d-wasm-agent-1 ps | grep spin
78191 0        /bin/containerd-shim-spin-v1 -namespace k8s.io -id 1a47549b3bf9a
78316 0        {youki:[2:INIT]} /bin/containerd-shim-spin-v1 -namespace k8s.io
81368 0        /bin/containerd-shim-spin-v1 -namespace k8s.io -id 3e06901e75d51
81609 0        {youki:[2:INIT]} /bin/containerd-shim-spin-v1 -namespace k8s.io
81745 0        /bin/containerd-shim-spin-v1 -namespace k8s.io -id 6a0e81d3fca70
81789 0        {youki:[2:INIT]} /bin/containerd-shim-spin-v1 -namespace k8s.io
```

Increase replica count to 10 and verify.

```
kubectl scale deploy wasm-spin --replicas=10
deployment.apps/wasm-spin scaled

kubectl get deploy wasm-spin
NAME        READY   UP-TO-DATE   AVAILABLE   AGE
wasm-spin   10/10   10           10          7m
```

Exec onto node 1 and show the increased number of containerd spin shims (one for each replica).

```
docker exec -it k3d-wasm-agent-1 ash
ps | grep spin
```

List running containers.

```
ctr task ls
```

Copy the long task ID of one of the containers that matches a spin shim PID and paste it on the following command.

```
ctr containers info <paste task ID>
```

Scroll up near the top to find the Wasm runtime.

```
    "Runtime": {
        "Name": "io.containerd.spin.v1",
```

## Clean-up

### Kubernetes clean-up

If you don't plan on keeping the k3d cluster, you can delete it with the following command. This will delete all cluster resources including the Deployment, load balancer, and Ingress. Be sure to use your cluster name.

```
$ k3d cluster delete wasm
```

If you followed along on an existing cluster that you plan to keep and only wish to delete the resources deployed as part of this guide you can run the following commands.

```
$ kubectl delete -f app.yml
deployment.apps "wasm-spin" deleted
service "svc-wasm" deleted
ingress.networking.k8s.io "ing-wasm" deleted

$ kubectl delete runtimeclass rc-spin
runtimeclass.node.k8s.io "rc-spin" deleted
```

### Docker clean-up

As part of the lab, you created a Docker image and pushed it to a registry. 

You may want to delete if from the registry.

If you tested the app with Docker, you will still have a Docker containiner running on your system. Delete it with the following command be sure to use the name of the container on your host.

```
$ docker rm <id-of-container-on-your-system> -f
```

Now you can delete the image from your host. Be sure to substitute the name of your image.

```
$ docker rmi nigelpoulton/docker-wasm:spin-0.1
```

### Directory clean-up

When you created the app with `spin new` and `spin build` you got a new directory called `dockercon` containing all the application artifacts. Use your favourite tool to delete the directory and all files in it. **Be sure to delete the correct directory!**
