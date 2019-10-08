#!/bin/bash

pub_key=${@}

if [ -z "$pub_key" ]; then
  echo "You need to supply a public key (taken from initialNodesSk.pem) to run this script!"
  exit 1
fi

jq_installed=$(command -v jq >/dev/null 2>&1)

if [ "$jq_installed" = false ]; then
  echo "jq is required to run this script."
  echo "Please install it using sudo apt-get install jq"
  exit 1
fi

rm -rf nodesSetup.json
wget -q https://raw.githubusercontent.com/ElrondNetwork/elrond-config/master/nodesSetup.json
address=$(cat nodesSetup.json | jq ".initialNodes[] | select(.pubkey == \"${pub_key}\") | .address" | tr -d '"')
rm -rf nodesSetup.json

echo "Your address is ${address}"
