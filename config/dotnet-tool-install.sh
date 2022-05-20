#!/bin/sh

# Install all tools passed at the command line. This will install directly into
# the /usr/local/bin directory so the tools are available for all users, i.e.
# the user that will be created by dew for the transient container.
dotnet tool install --tool-path /usr/local/bin "$@"
