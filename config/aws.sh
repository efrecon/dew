#!/bin/sh

# Install session manager
if [ ! -x "/usr/local/bin/session-manager-plugin" ]; then
  curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "/tmp/session-manager-plugin.rpm"
  yum install -y /tmp/session-manager-plugin.rpm
  session-manager-plugin
fi
