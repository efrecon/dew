# Docker EveryWhere

We are in 2021! Docker can be used to provide a consequent working environment
across platforms. This script aims at running development-oriented environments
in the form a Docker container based on an image with the tooling of your
requiring, from within the current directory. In most cases, this allows for
transient environments, as all is required on the host is a Docker daemon and
images that can be garbage collected once done. Consquently, you should be able
to keep OS installation to a minimal and run most activities from within
containers and in a transparent way.

This scripts takes some inspiration from [lope] with the addition of being able
to read configurations for known environments. This minimises typing and
automates all the necessary command-line options for making a given environment
possible. Configurations are simply `env` files placed in a sub-directory of the
`$XDG_CONFIG_HOME` directory.

  [lope]: https://github.com/Crazybus/lope

## Examples

All these examples suppose that you have made `dew.sh` available from your
`$PATH`.

### Busybox

To get a busybox shell in the current working directory, in order to more easily
test POSIX compliance of your scripts, or their ability to run in an embedded
system, you could run the following command:

```shell
dew.sh busybox
```

This simple command builds upon many of the "good" defaults. It will:

+ Give you an interactive `ash` prompt with the content of the current directory
  visible. `ash` is picked up from a list of plausible shells, as one of
  existing in `busybox`.
+ Forbid access to parent directories, or directories elsewhere on the disk.
  This is a security feature.
+ Arrange for the container to run the shell with your user and group ID, so
  file access, creation and permissions work as expected.
+ Automatically forward the values of most of your environment variables to the
  container.
+ Arrange for the container to have a minimal environment mimicing your local
  environment: there will be a HOME directory, the same as yours. There will be
  a user and a group, with the same IDs as yours.

### Alpine

Running the following command provides more or less the same prompt as above.
Note however that, since the default is to run impersonated as yourself, you
will end up having an Alpine promt where you cannot install additional software
(as you will not be able to `sudo`).

```shell
dew.sh alpine
```

You can give yourself access to the host's Docker daemon and see other
containers that are running by running the following command:

```shell
dew.sh --docker alpine
```

In practice this will download a version of the Docker client on your local
machine, place the client in a sub-directory of the XDG cache (i.e. as specified
by `$XDG_CACHE_HOME` or the default `${HOME}/.cache`) and mount the binary into
the Alpine Docker container. Go binaries are statically compiled, making this
possible across distributions and libc implementations. In addition, `dew` will
have arranged for the impersonated user within the container to be a member of
the `docker` group, under the same ID as the local `docker` group as associated
to the UNIX domain socket at `/var/run/docker.sock`.

From within the Alpine container, the following command will therefor work as
expected and show all running containers on the host. One of these containers
will be your container. It will have been automatically be named to
`dew_alpine_` followed by the PID of the `dew` process at the time of its
creation. You should even be able to kill yourself by removing the container
with the Docker CLI!

```shell
docker ps
```

### Python

To get an interactive python, you could run the following command:

```shell
dew python
```

Setting up python uses a specific environment configuration
[file](./config/python.env) that sepcifies a number of variables that will be
used by `dew` when creating the container. In practice, this sets the shell to
use for the environment to `-`, which is understood by `dew` as running the
default `python` image from the Docker hub, but as your regular user.

### Tcl

In the same vein, getting an interactive Tcl prompt is as easy as running the
following command.

```shell
dew tclsh
```

This uses a slightly more advanced environment configuration
[file](./config/tclsh.env). The configuration arranges for a user-level specific
[entrypoint](./config/tclsh.sh) to be injected into the container and used as
the shell. The purpose of this is to be able to provide the user with a
`.tclshrc` file in its `$HOME` directory. The `.tclshrc` is picked from its
default location in the [image][mini-tcl] and arranges for a readline-capable
Tcl prompt with a coloured prompt.

  [mini-tcl]: https://hub.docker.com/r/efrecon/mini-tcl/

### Kubernetes

To operate against a Kubernetes cluster, you could run a command similar to the
following one:

```shell
dew kubectl get pods --all-namespaces
```
