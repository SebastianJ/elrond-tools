#!/bin/bash

# Elrond script updater
script_repo="$HOME/elrond/script/elrond-go-scripts-v2"
destination_folder="$HOME/elrond/script"

echo "Updating elrond-go-scripts-v2 in $script_repo"

cd $script_repo
git fetch
git checkout --force master
git pull

echo "Updated git repo (fetch/checkout/pull)"

echo "Copying new release to $destination_folder"

rm -rf $destination_folder/auto-updater.sh $destination_folder/config $destination_folder/script.sh
cp -R $script_repo/auto-updater.sh $script_repo/script.sh $script_repo/config .
rm -rf $destination_folder/config/variables.cfg
cp $destination_folder/variables.cfg $destination_folder/config/

echo "Successfully updated elrond-go-scripts-v2!"
