#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
pushd $DIR
aws --profile mfa ec2 run-instances --region us-east-2 --cli-input-json file://ec2-instance-props.json --user-data file://ec2-userdata
popd
