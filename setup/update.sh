#!/bin/bash
version="0.0.1"

usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   -p path      the go path where files should be installed, will default to $GOPATH
   -n name      the display name for the node
   -m name      systemd service name (excluding .service)
   -s           start the node process after setup is completed
   -g           force reinstallation of gvm and go
   -h           print this help
EOT
}

set_default_option_values() {
  if [ -z "$go_path" ]; then
    if [ -z "$GOPATH" ]; then
      go_path=$HOME/go
    else
      go_path=$GOPATH
    fi
  fi

  if [ -z "$start_node" ]; then
    start_node=false
  fi
  
  if [ -z "$install_gvm" ]; then
    install_gvm=false
  fi
}

while getopts "p:n:m:sgh" opt; do
  case ${opt} in
    p)
      go_path="${OPTARG%/}"
      ;;
    n)
      display_name="${OPTARG}"
      ;;
    m)
      systemd_service_name="${OPTARG}"
      ;;
    s)
      start_node=true
      ;;
    g)
      install_gvm=true
      ;;
    h|*)
      usage
      exit 1
      ;;
  esac
done

shift $((OPTIND-1))

initialize() {
  full_reinstall=true
  set_default_option_values
  set_paths
  
  if [ ! -z "$systemd_service_name" ]; then
    sudo systemctl stop $systemd_service_name
  fi
  
  if [ "$full_reinstall" = true ]; then
    rm -rf $base_path && mkdir -p $base_path
  fi
  
  set_formatting
}

set_paths() {
  base_path=$go_path/src/github.com/ElrondNetwork
  node_path=$base_path/elrond-go
  config_path=$base_path/elrond-config
  keys_archive=$HOME/keys.tar.gz
  
  echo "Base path: ${base_path}"
  echo "Node path: ${node_path}"
  echo "Config path: ${config_path}"
  
  export GOPATH=$go_path
  export PATH="$PATH:${go_path}/bin"
}

set_formatting() {
  bold_text=$(tput bold)
  normal_text=$(tput sgr0)
  black_text=$(tput setaf 0)
  red_text=$(tput setaf 1)
  green_text=$(tput setaf 2)
  yellow_text=$(tput setaf 3)
}

install_gvm() {
  if [ "$install_gvm" = true ]; then
    sudo rm -rf $HOME/.gvm
    touch $HOME/.bash_profile

    source <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)

    source $HOME/.gvm/scripts/gvm

    echo "[[ -s "$HOME/.gvm/scripts/gvm" ]] && source \"/$HOME/.gvm/scripts/gvm\"" >> $HOME/.bash_profile
    echo "export GOPATH=$go_path" >> $HOME/.bash_profile
    echo "export PATH=\"$PATH:${go_path}/bin\"" >> $HOME/.bash_profile
  
    source $HOME/.bash_profile
  
    gvm install go1.13.1 -B
    gvm use go1.13.1 --default
  fi
}

install() {
  release_tag="$(curl --silent "https://api.github.com/repos/ElrondNetwork/elrond-${1}/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')"
  cd $base_path && git clone https://github.com/ElrondNetwork/elrond-${1}
  cd elrond-${1}  
  git fetch
  git checkout --force tags/${release_tag}
  git pull
  success_message "Successfully fetched the latest ${1} release ${release_tag}"
}

copy_configuration_files() {
  cp $config_path/*.* $node_path/cmd/node/config
  success_message "Successfully copied the configuration files over to ${node_path}/cmd/node/config"
}

build_binaries() {
  cd $node_path
  GO111MODULE=on go mod vendor
  cd cmd/node && go build -i -v -ldflags="-X main.appVersion=$(git describe --tags --long --dirty)"
  success_message "Successfully built the node binary."
}

generate_keys() {
  cd $node_path/cmd/keygenerator
  go build
  ./keygenerator
  
  cp initialBalancesSk.pem $node_path/cmd/node/config
  cp initialNodesSk.pem $node_path/cmd/node/config
}

copy_keys() {
  cp $keys_archive $node_path/cmd/node/config
  cd $node_path/cmd/node/config
  tar -xzvf *.tar.gz && rm -rf *.tar.gz
  
  success_message "Successfully copied existing keys over to ${node_path}/cmd/node/config"
}

start_node() {
  if [ "$start_node" = true ]; then
    if [ ! -z "$systemd_service_name" ]; then
      sudo systemctl start $systemd_service_name
    else
      cd $node_path/cmd/node/ && ./node
    fi
  fi
}

update_display_name() {
  if [ ! -z "$display_name" ]; then
    sed -i "s/NodeDisplayName = \"[a-zA-Z0-9]*\"/NodeDisplayName = \"${display_name}\"/g" $node_path/cmd/node/config/config.toml
  fi
}

success_message() {
  echo ${green_text}${1}${normal_text}
}

warning_message() {
  echo ${yellow_text}${1}${normal_text}
}

error_message() {
  echo ${red_text}${1}${normal_text}
}

update() {
  echo "${bold_text}Updating Elrond...${normal_text}"
  
  initialize
  
  install_gvm
  
  install "config"
  install "go"
  copy_configuration_files
  build_binaries
  copy_keys
  update_display_name
  
  success_message "Sucessfully updated Elrond to ${release_tag}!"
  
  start_node
}

update
