#!/bin/sh

# Install git as it is used for `cdk init`
if command -v apk >/dev/null 2>&1; then
    apk add --no-cache git
elif command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y git
fi

# Upgrade npm to the latest, then install typescript and cdk globally, so they
# are available at the prompt. This doesn't pin versions, which might be against
# some dev practices.
npm update --location=global npm && npm install --location=global typescript aws-cdk-local aws-cdk
