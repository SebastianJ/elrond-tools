#!/bin/bash

# Elrond script updater

usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   --repo     path    the output path for compiled binaries
   --path     path    the go path where git repositories should be cloned, will default to $GOPATH
   --help             print this help section
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --repo) repo_path="${2%/}" ; shift;;
  --path) destination_path="${2%/}" ; shift;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

if [ -z "$repo_path" ]; then
  repo_path="$HOME/elrond/script/elrond-go-scripts-v2"
fi

if [ -z "$destination_path" ]; then
  destination_path="$HOME/elrond/script"
fi

update_repo() {
  echo "Updating elrond-go-scripts-v2 in $repo_path"

  if test -d $repo_path; then
    cd $repo_path
    git fetch >/dev/null 2>&1
    checkout_message=$(git checkout --force master)
    already_updated_message="Your branch is up to date"

    if [[ "$checkout_message" =~ "$already_updated_message" ]]; then
      echo "You already have the latest version of elrond-go-scripts-v2!"
    else
      git pull
      install_files
    fi
  else
    mkdir -p $repo_path
    cd $repo_path
    git clone https://github.com/ElrondNetwork/elrond-go-scripts-v2.git
    install_files
  fi
}

install_files() {
  echo "Copying new release to $destination_path"

  rm -rf $destination_path/auto-updater.sh $destination_path/config $destination_path/script.sh
  cp -R $repo_path/auto-updater.sh $repo_path/script.sh $repo_path/config $destination_path

  if test -f $destination_path/variables.cfg; then
    rm -rf $destination_path/config/variables.cfg
    cp $destination_path/variables.cfg $destination_path/config/
  fi

  echo "Successfully updated elrond-go-scripts-v2!"
}
