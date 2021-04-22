# Docker EveryWhere

We are in 2021! Docker can be used to provide a consequent working environment
across platforms. This script aims at running development-oriented environments
in the form a Docker container based on an image with the tooling of your
requiring, from within the current directory. In most cases, this allows for
transient environments, as all is required on the host is a Docker daemon.
Consquently, you should be able to keep OS installation to a minimal and run
most activities from within containers and in a transparent way.

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
  visible.
+ Forbid access to parent directories, or directories elsewhere on the disk.
  This is a security feature.
+ Arrange for the container to run the shell with your user and group ID, so
  file access, creation and permissions work as expected.
+ Automatically forward the values of most of your environment variables to the
  container.
