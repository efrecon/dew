#!/bin/sh

# Install session manager
if [ ! -x "/usr/local/bin/session-manager-plugin" ]; then
  curl -sSL "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" \
    -o /tmp/session-manager-plugin.rpm
  yum install -y /tmp/session-manager-plugin.rpm
  session-manager-plugin
fi

if ! command -v sam >/dev/null 2>&1; then
  curl -sSL "https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-x86_64.zip" \
    -o /tmp/aws-sam-cli-linux.zip
  yum install -y unzip
  unzip /tmp/aws-sam-cli-linux.zip -d /tmp/aws-sam-cli-installer
  /tmp/aws-sam-cli-installer/install
  sam --version
fi