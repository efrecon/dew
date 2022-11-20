#!/bin/sh

# This is an awslocal wrapper inspired by
# https://github.com/localstack/awscli-local#alternative

AWS_ACCESS_KEY_ID="test"
AWS_SECRET_ACCESS_KEY="test"
AWS_DEFAULT_REGION=${DEFAULT_REGION:-${LOCALSTACK_DEFAULT_REGION:-$AWS_DEFAULT_REGION}}
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_DEFAULT_REGION
exec aws \
  --endpoint-url="http://${LOCALSTACK_HOST:-localhost}:4566" \
  "$@"
