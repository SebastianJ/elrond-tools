#!/bin/bash

if [ -z "$GOPATH" ]; then
  GOPATH=$HOME/go
fi

config_path=$GOPATH/src/github.com/ElrondNetwork/elrond-go/cmd/node/config/config.toml
echo "Changing NodeDisplayName to ${@} in $config_path"
sed -i "s/NodeDisplayName = \"[a-zA-Z0-9]*\"/NodeDisplayName = \"${@}\"/g" $config_path
