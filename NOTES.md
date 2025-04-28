We should:

+ Test if it is possible to impersonate in the first place, this requires for
  the image to have a user that is empty or root (or the ability to run as root,
  knowing we will be su:ing into a proper user later.)  Probably best is to
  `--user root` and then inject `su.sh` so that it elevates to the user in the
  end.
+ Collect the entrypoint and the original command (see below)
+ When we inject, save the original entire image (with tag) in the comment, just
  that. This way, we will be able to collect the entrypoint and original command.
+ Once we have the entrypoint and the command, we should be able to leave aside
  the `DEW_SHELL` stuff as much as possible, and ignore most cases where we are
  looking for extra arguments or not, meaning we would be able to simplify the
  logic. In other words: we start from scratch again, with a single if-statement
  around impersonation (where the complexity comes in).

To know what can be output from the `--format` command, run the following:

```shell
docker image inspect --format '{{ json . }}' | jq
```

So, to get the entrypoint and the command, the following will do. Note that we
need to perform tests as these might be `sh -c` sometimes, and also most of the
time they would be a JSON array of elements.

```shell
docker image inspect --format '{{ .Config.Entrypoint }}'
docker image inspect --format '{{ .Config.Cmd }}'
```
