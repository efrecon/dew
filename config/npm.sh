#!/bin/sh

# Install man as it is used for `npm help`
if command -v apk >/dev/null 2>&1; then
    apk add --no-cache man
elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y man
fi

# Upgrade npm to the latest
npm update -g npm
