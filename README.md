# docker-flexvol

A [FlexVolume](https://github.com/kubernetes/community/blob/master/contributors/devel/flexvolume.md) driver for kubernetes which allows you to mount [Docker](https://docs.docker.com/engine/admin/volumes/volumes/) volumes to your kubernetes pods.

## Status

Proof of concept

## Using

This flex volume plugin can start a fresh docker volume from a specified container image and attach it to the kubernetes
pod. This is useful for scenarios where you need your pod to access a bunch of files and if already have that data
as a docker container image, you can just specify the container image name and the volume name in your kubernetes
pod definition and make it available to whatever is running in the pod.

### Installing

In order to use the flexvolume driver, you'll need to install it on every node in the kubelet `volume-plugin-dir`. By default this is `/usr/libexec/kubernetes/kubelet-plugins/volume/exec/`

You need a directory for the volume driver vendor, so create it:

```
mkdir -p /usr/libexec/kubernetes/kubelet-plugins/volume/exec/dims.io~docker-flexvol
```

Then drop the binary in there and set the execute permission:

```
mv docker-flexvol.sh /usr/libexec/kubernetes/kubelet-plugins/volume/exec/dims.io~docker-flexvol/docker-flexvol
chmod +x /usr/libexec/kubernetes/kubelet-plugins/volume/exec/dims.io~docker-flexvol/docker-flexvol
```

You can now use Docker volumes as usual!

### Pod Config

An example pod config would look like this. Note the `image` and `name` parameters. The `image` is the name of the
container that we need to start. `name` is the name of the volume we need to mount.

Note that `image` is mandatory, `name` is optional. If `name` is not specified all the contents of the container are
made available to the pod.

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: nginx
  namespace: default
spec:
  containers:
  - name: nginx
    image: nginx
    volumeMounts:
    - name: test
      mountPath: /data
    ports:
    - containerPort: 80
  volumes:
  - name: test
    flexVolume:
      driver: "dims.io/docker-flexvol"
      options:
        image: "my-container-image"
        name: "/data-store"
```

This will use the `/data-store` volume on the `my-container-image` and mount it on the nginx pod under `/data` directory.  

Run `docker ps -a` and find the container with image "my-container-image", that's the one that has the docker volume. this
should be in the `Created` state. Look for the `Source` directory, it will be something like
`/var/lib/docker/volumes/2ec90b1efa7b1f51913882d035192a450810419d72b56814a1332b31457aa356/_data`

Run `kubectl exec -it nginx -- /bin/bash`, cd to `/data` directory and create a file with say a datestamp. Now
look under the directory above and you should see the same file and contents.

### Container Image with pre-defined volume

To create a Container Image with Volume, save content below into Dockerfile in an empty directory:

```
FROM alpine
ADD https://raw.githubusercontent.com/kubernetes/kubernetes/master/README.md /data-store/README.md
VOLUME ["/data-store"]
ENTRYPOINT ["/bin/sh"]
```

Create a docker image using 

`docker image build -t my-container-image .`

Test the image using docker

`docker run --name my-container-1 -it my-container-image`

Now this container image is ready to be used with this flexvolume driver. When you use this image with the pod config
above, you can exec into the pod and see the file

```
[dims@bigbox 16:15] ~ ⟩ kubectl exec -it nginx -- /bin/bash
root@nginx:/# cd /data
root@nginx:/data# ls -altr
total 12
-rw-------  1 root root 3241 Jan  1  1970 README.md
drwxr-xr-x  2 root root 4096 Aug 18 20:15 .
drwxr-xr-x 32 root root 4096 Aug 18 20:15 ..
```
