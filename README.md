# Docker EveryWhere, `dew`

We are past 2020! Docker can be used to provide the same working environment
across platforms. `dew` aims at development workflows consisting of Docker
containers based on images with the tooling of your requiring. These containers
will run from within the current directory and as your current user inside the
container. In most cases, this allows for transient environments, as all that is
required on the host is a Docker daemon and images that can be garbage collected
once done (containers are automatically removed once they have ended).

Running `dew` increases security by encapsulating only the relevant part of the
file system required for a workflow. In addition, it should save you from
"dependency hell". You should be able to keep OS installation to a minimal and
run most activities from within containers in a transparent way. These
containers will have your shell code, your configuration, but all binaries and
dependencies will remain in the container and disappear automatically once done.

For the technically inclined, `dew` is a shortcut to the command below.
Actually, the [implementation](#implementation) is a bit more complex, but in
the same spirit:

```shell
docker run \
  -it --rm \
  -v $(pwd):$(pwd) \
  -w $(pwd) \
  -u $(id -u):$(id -g) \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --network host \
  xxx
```

This script takes some inspiration from [lope] with the addition of being able
to read configurations for known environments. This minimises typing and
automates all the necessary command-line options for making a given environment
possible. Configurations are simply `env` files placed: in a sub-directory of
the current directory called `.dew.d`, in a sub-directory of the
`$XDG_CONFIG_HOME` directory, or under the [`config`](./config/) directory of
this repository. To get a list of known configurations, run `dew` with the `-l`
option.

  [lope]: https://github.com/Crazybus/lope

**Note**: This project uses git [submodules], use one of the two commands to
make sure you have a copy of the submodules. Without the modules, the main
script will not even start!

```shell
git clone --recursive https://github.com/efrecon/docker-images.git
git submodule update --init --recursive
```

To catch up with changes, run the following:

```shell
git submodule update --init --recursive
```

  [submodules]: https://git-scm.com/book/en/v2/Git-Tools-Submodules

## Examples

All these examples suppose that you have made `dew.sh` available from your
`$PATH`. They will also work if you symlink `dew` to a place where you have this
repository installed, and arrange for the `dew` symlink to be in your `$PATH`.
To make it quicker to type, you probably want to call the symbolic link `dew`
instead of `dew.sh`.

### Busybox

To get a busybox shell in the current working directory, in order to more easily
test POSIX compliance of your scripts, or their ability to run in an embedded
system, you could run the following command:

```shell
dew.sh busybox
```

This simple command builds upon many of the "good" defaults. It will:

+ Give you an interactive `ash` prompt with the content of the current directory
  visible. `ash` is picked up from a list of plausible shells, as one existing
  in `busybox`.
+ Forbid access to parent directories, or directories elsewhere on the disk.
  This is a security feature.
+ Arrange for the container to run the shell with your user and group ID, so
  file access, creation and permissions work as expected.
+ Automatically forward the values of most of your environment variables to the
  container.
+ Arrange for the container to have a minimal environment mimicing your local
  environment: there will be a `$HOME` directory, the same as yours. There will
  be a user and a group, with the same IDs as yours.

To verify this, assuming that you have a copy of this repository and its
[submodules] at `/home/emmanuel/dev/foss/dew` you could run the following
command from that directory.

```shell
./dew.sh busybox find $HOME -type d | grep -v .git
```

This should output the following. `.git` information has been removed to keep
this output sizeable. You can verify that only the relevant parts of the
filesystem have been made available to the container, but also that the
container has accessed to the `$HOME` variable and that it matches your own
`$HOME` on the host.

```text
/home/emmanuel
/home/emmanuel/dev
/home/emmanuel/dev/foss
/home/emmanuel/dev/foss/dew
/home/emmanuel/dev/foss/dew/libexec
/home/emmanuel/dev/foss/dew/libexec/docker-rebase
/home/emmanuel/dev/foss/dew/libexec/docker-rebase/lib
/home/emmanuel/dev/foss/dew/libexec/docker-rebase/lib/mg.sh
/home/emmanuel/dev/foss/dew/libexec/docker-rebase/lib/mg.sh/spec
/home/emmanuel/dev/foss/dew/libexec/docker-rebase/lib/mg.sh/spec/support
```

### Alpine

Running the following command provides more or less the same prompt as above.
Note however that, since the default is to run impersonated as yourself, you
will end up having an Alpine promt where you cannot install additional software
(as you will not be able to `sudo`).

```shell
dew.sh alpine
```

To run as root, do the following instead:

```shell
dew.sh -r alpine
```

Without being root, and as long as your local user on the host has access to the
Docker daemon, you can give yourself access to the host's Docker daemon and see
other containers that are running by running the following command:

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

From within the Alpine container, the following command will therefore work as
expected and show all running containers on the host. One of these containers
will be your container. It will have been automatically be named to
`dew_alpine_` followed by the PID of the `dew` process at the time of its
creation. You should even be able to kill yourself by removing the container
with the Docker CLI!

```shell
docker ps
```

If you run the command from the root directory of this repository, you can even
start yet another `dew` environment from the prompt within the first `dew`
container. In other words, from the Alpine prompt in the container, running the
following command will open yet another clean environment in another container.
To verify this, you should see that running `dew.sh` downloads a new copy of the
Docker client, as it does not exist in the cache from within the first
container.

```shell
dew.sh --docker alpine
```

### Python

To get an interactive python, you could run the following command:

```shell
dew.sh python
```

Setting up python uses a specific environment configuration
[file](./config/python.env). It specifies a number of variables that will be
used by `dew` when creating the container. In practice, this sets the shell to
use for the environment to `-`, which is understood by `dew` as running the
default `python` image from the Docker hub, but as your regular user.

### Node

To get a bash prompt where you can run both `npm` and `node`, run the following
command. The entrypoint for the node image is `node`, but the default for `dew`
when running with impersonation is to inject its own [`su.sh`](./su.sh) script
as an entrypoint. The script will ensure a minimal HOME environment for a user
named after yours. This is why the following command provides a bash prompt,
rather than a `node` prompt. In that specific case, you might also notice that
you might become the user called `node` (and not your username). This is because
the default Docker node image already has a user at uid `1000` with the name
`node`.

```shell
dew.sh node
```

If you instead want to get an interactive `node` prompt, run the following. This
suppresses injection of [`su.sh`](./su.sh) as described above, reverting to the
regular behaviour.

```shell
dew.sh -s - node
```

### Tcl

In the same vein, getting an interactive Tcl prompt is as easy as running the
following command.

```shell
dew.sh tclsh
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
following one. The command uses yet another configuration
[file](./config/kubectl.env), this time with the main goal of passing your
`$HOME/.kube/config` file to the container.

```shell
dew.sh kubectl get pods --all-namespaces
```

### lazydocker

To run lazydocker to analyse what is currently running at your local Docker
daemon, run the following command:

```shell
dew.sh --docker --root --shell - lazyteam/lazydocker
```

As this is almost too long, even when using the short options, there is a
ready-made configuration for [lazydocker](./config/lazydocker.env). The
configuration arranges to run under your account with impersonation and for
configuration settings to be saved at their standard location in your `$HOME`
directory. This requires [rebasing](#dew_rebase) the image on top of
`busybox:latest`. Instead of the longer command above, you should be able to
run:

```shell
dew.sh lazydocker
```

## Command-Line Options

`dew` offers a number of command-line options, possibly followed by a
double-dash `--` to mark the end of the options, followed by the name of a
Docker image (or the name of a tailored environment found under the
configuration path), followed by arguments that will be passed to the Docker
container at its creation (the `COMMAND` from a Dockerfile). Pass the option
`--help` to get a list of known options.

## Environment Variables

`dew` can also be configured using environment variables, these start with
`DEW_`. Command-line options, when specified, have precedence over the
variables. Apart from empty-lines and comments, the `DEW_`-led variables are the
only variables that can be set in the environment configuration files found
under the configuration path.

### `DEW_CONFIG_PATH`

This variable is a colon separated list of directories where `dew` will look for
environment configuration files, i.e. files which basename matches the first
command-line argument after all the options. `dew` will look for files without
an extension, or the extension `.env`, in that order. The default for the
configuration path is the directory `dew` under `$XDG_CONFIG_HOME`, followed by
the `config` directory under this repository. When `XDG_CONFIG_HOME` does not
exist, it defaults to `$HOME/.config`.

### `DEW_SOCK`

This variable contains the location of the Docker UNIX domain socket that will
be passed to the container created by `dew`. The default is to pass the socket
at `/var/run/docker.sock`. When the value of this variable is empty, the socket
will not be passed to the container. Note that this is not the same as the
[`DEW_DOCKER`](#dew_docker) variable. Both need to be set if you want a Docker
CLI in your container.

### `DEW_BLACKLIST`

This variable is a comma-separated list of environment variables that will
**not** be passed to the container where impersonation is turned on (see
[`DEW_IMPERSONATE`](#dew_impersonate)). The default is
`SSH_AUTH_SOCK,TMPDIR,PATH`.

### `DEW_IMPERSONATE`

This variable is a type or a boolean. When set to `1`, the default,
impersonation will happen, i.e. the process or interactive prompt inside the
container will run under a user with the same user and group identifiers as the
ones of the calling user. In addition, in interactive containers, the user
inside the container will be given the same `HOME` directory as the original
user, albeit empty (except perhaps for the current path, see
[`DEW_MOUNT`](#dewmount)). Impersonation works by running the container as
`root`, but injecting an impersonation script that will setup a minimal
environment inside the container before becoming to relevant user and group.

When the variable is set to `minimal`, minimal impersonation will happen
instead. This means that the identifier of the first regular user present inside
the image will be used for impersonation. The container is then run using the
[`--user`][user] option, but [`fixuid`][fixuid] is injected and used to arrange
for proper access rights for files.

  [user]: https://docs.docker.com/engine/reference/run/#user
  [fixuid]: https://github.com/boxboat/fixuid

### `DEW_INTERACTIVE`

This variable is a boolean. When set to 1, the default, interaction will be
enabled within the container. In practice, this means that the Docker run
command will use the options `-it -a stdin -a stdout -a stderr`. It is possible
to turn this off, but re-adding a single `-i` through the
[`DEW_OPTS`](#dew_opts) variable for proper pipe support. See
[bat](./config/bat.env) for an example.

### `DEW_DOCKER`

This variable is a boolean. When set to 1, a version of the Docker client should
be injected into the destination container. The default is `0`, i.e. no Docker
CLI available. Note that you need [`DEW_SOCK`](#dew_sock) to point to the UNIX
domain socket to arrange for the Docker CLI client in the container to be able
to access the host's Docker daemon. When impersonating, user inside the
container will be made a member of the `docker` group in order to have the
proper permissions.

### `DEW_MOUNT`

This variable expresses the number of levels up the directory hierarchy,
starting from the current one, should be mounted into the container. A negative
number turns off the function entirely. When positive, the working directory in
the container maps to the current directory. Setting this to strictly positive
values will facilitate accessing (development) files upwards in the tree. In
other words:

+ Setting `DEW_MOUNT` to `0` (the default) mounts the current directory inside
  the container and makes it the working directory.
+ Setting `DEW_MOUNT` to `1` mounts the parent of the current directory inside
  the container, and makes the current directory the working directory. This
  enables the container to access all files and directories contained in the
  parent directory.

### `DEW_OPTS`

The content of this variable is blindly passed to the `docker run` command when
the container is created. It can be used to pass further files or directories to
the container, e.g. the k8s configuration file, or an rc file.

Note that in the content of this variable, any string named after one of the
documented [variables](#variables-accessible-to-resolution), but surrounded by
`%`, e.g. `%DEW_SHELL%`, will be replaced by the value of that variable.

### `DEW_SHELL`

This variable can contain the path to a shell that will be run for interactive
commands. The default is to have an empty value, which will look for the
following possible shells in the container, in that order: `bash`, `ash`, `sh`.

### `DEW_DOCKER_VERSION`

This variable is the version of the Docker client to download and inject in the
container when running with the `-d` (`--docker`) command-line option, or when
the [`DEW_DOCKER`](#dew_docker) variable is set to `1`.

### `DEW_INSTALLDIR`

This variable is the directory where to install binaries inside the container.
This defaults to `/usr/local/bin`, a directory which is part of the default
`PATH` of most distributions.

### `DEW_REBASE`

This variable will [rebase] the main image passed as the first argument on top
of the image given to the option. This can be handy when running with slimmed
down images that only contain relevant binaries, and when you, for example,
desire a shell and related utilities at an interactive prompt in such an image.
Rebasing will generate a new image, and this will happen once and only once per
pair of images.

  [rebase]: https://github.com/efrecon/docker-rebase

### `DEW_XDG`

When the value of this variable is not empty, `dew` will create 4 directories
under the [XDG] standard directories, named after the value of that variable
(i.e. sub-directories of `$XDG_DATA_HOME`, `$XDG_CONFIG_HOME`, `$XDG_STATE_HOME`
and `$XDG_CACHE_HOME`). Each directory that was successfully created, will be
mounted into the container for read and write. Using sub-directories is
compatible with most tools and enforces configuration isolation as the binaries
running in the container will not be able to read any other XDG configuration
files than the selected ones.

  [XDG]: https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html

### `DEW_PATHS`

This variable should contain a space-separated list of path specifications.
These specifications will point to files and/or directories that will be created
before the container is created. This can be used in addition to the
[`DEW_XDG`](#dew_xdg) variable for hidden setting files and similar. Path
specifications should contain the following items, separated by the colon `:`
sign:

+ The path to the file or directory to create (mandatory)
+ The type of the path: `f` or `-` for a file, `d` for a directory. When empty,
  the default, a file will be created through `touch`.
+ A template (file or directory) to initialise the content of the file or
  directory. In this specification `%` enclosed variable
  [names](#variables-accessible-to-resolution) will be replaced by their
  content.
+ The access specification for the path, compatible with the `chmod` command,
  e.g. `0700` or `ug+rw`. When empty, the default, no `chmod` will be performed
  and the file or directory will be created with the user account's default
  mask.
+ The owner of the file (a name or an integer). When empty, the default, the
  owner will not be changed and be the user running the script.
+ The group owner of the file (a name or an integer). When empty, the default,
  the group will not be changed and be the one of the user running the script.

### `DEW_RUNTIME`

This variable should contain the name of a runtime client able to create OCI
containers using the docker CLI command-line options. By default, this is an
empty string, in which case the first existing client out of the list contained
in the `DEW_RUNTIMES` (note the terminating `S`) will be picked. `docker` is
first in this list for backwards compatibility.

### `DEW_INJECT`

This variable implements a single `RUN` command from a Dockerfile on the cheap.
The command that it contains will be first used as the entrypoint on the image
pointed at by the `DEW_IMAGE` variable (or corresponding command-line option).
Once done, a snapshot of the resulting container will be stored in a local
image, using a tag that uniquely depends on the content of the command. Then,
everything will proceed as described in this manual, but using the new image.
Image generation will only happen if the content of the command changes. When
the command is a valid (local) path, its content will be used instead.

Note that in the content of this variable, any string named after one of the
documented [variables](#variables-accessible-to-resolution), but surrounded by
`%`, e.g. `%DEW_SHELL%`, will be replaced by the value of that variable.

### `DEW_INJECT_ARGS`

This variable contains arguments that are blindly passed to the
[injected](#dewinject) command at the time of image creation. This facilitates
the reuse of the same injected command, with varying arguments. You could, for
example, reuse a command that performs generic package installation and give it
varying packages for the implementation of a container.

Note that in the content of this variable, any string named after one of the
documented [variables](#variables-accessible-to-resolution), but surrounded by
`%`, e.g. `%DEW_SHELL%`, will be replaced by the value of that variable.

## Variables Accessible to Resolution

The variables accessible are all the variables starting with `DEW_` and
described in the section [above][#environment-variables]. In addition, it is
possible to use, when relevant:

+ `DEW_CONFIGDIR`: The directory hosting the `.env` configuration file.
+ `DEW_ROOTDIR`: The directory hosting the main `dew.sh` script (resolved).

## Implementation

In many cases, this script goes a few steps further than the `docker run`
command highlighted in the introduction.

First of all, in encapsulates all processes running in the container around
`tini` using the `--init` command-line option of the Docker `run` sub-command.
This facilitates signal handling and ensures that all sub-processes will
properly terminate without waiting times.

Second, it pushes timezone information from the host into the container for
accurate time readings.

Third, and most importantly, `dew` will often not directly add the `--user`
option to the `run` subcommand, but still ensures that the process(es) is/are
run under your user and group. To this end, `dew` injects a
[su](./su.sh)-encapsulating script into the container and arranges for that
script to be run as the entrypoint. The script will perform book-keeping
operations such as creating a matching user and group in the "OS" of the
container, including a home at the same location as yours. The script will also
ensure that your user inside the container is a member of the `docker` group to
facilitate access to the mounted Docker socket. Once all book-keeping operations
have been performed, the script becomes "you" inside the container and execute
all relevant processes under that user with `su`.

Encapsulated behind the main `su`, processes should see an empty (but existing!)
`$HOME`, apart from the current directory where the `dew` container was started
from. That directory will be populated with all files accessible under that part
of the filesystem tree. Some tools require more files to be accessible for
proper operation (configuration files, etc.). In that case, you should be able
to add necessary files through passing additional mounting options to the docker
`run` subcommand, e.g. [kubectl](./config/kubectl.env) or
[lazydocker](./config/lazydocker.env). The [su](su.sh)-encapsulating script
requires a number of common Linux utilities to be present in the target
container. When running with slimmed down images, you can make sure to provide
such an environment through the `--rebase` option or its equivalent
[`DEW_REBASE`](#dew_rebase) variable.

## Requirements

`dew` has minimal requirements and is implemented in pure POSIX shell for
maximum compatibility across platforms and operating systems. `dew` only uses
the command-line options of `sed`, `grep` etc. that available under their
`busybox` implementation. When creating users and groups, [`su.sh`](./su.sh)
tries to use the tools available in the base OS used by the container. Finally,
when [rebasing](#dew_rebase) is necessary, [rebase.sh][rebase] will require `jq`
to be installed on the host system.
