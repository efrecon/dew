#!/bin/sh

ln -s /scripts/tclshrc "$HOME/.tclshrc"
exec tclsh8.6 "$@"