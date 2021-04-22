# Docker EveryWhere

We are in 2021! Docker can be used to provide a consequent working environment
across platforms. This script aims at running development-oriented environment
in the form a Docker container based on an image with the tooling of your
requiring, from within the current directory. In most cases, this allows for
transient environment, as is required on the host is a Docker daemon.
Consquently, you should be able to keep OS installation to a minimal and run
most activities from within containers and in a transparent way.

This scripts takes some inspiration from [lope] with the addition of being able
to read configurations for known environments. This minimises typing and
automates all the necessary command-line options for making a given environment
possible. Configurations are simply `env` files placed in a sub-directory of the
`$XDG_CONFIG_HOME` directory.

  [lope]: https://github.com/Crazybus/lope
