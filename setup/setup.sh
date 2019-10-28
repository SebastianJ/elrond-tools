#!/bin/bash
version="0.0.2"
script_name="setup.sh"
default_go_version="go1.13.1"

#
# Arguments/configuration
#
usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   --nodes                    count   the number of nodes you want to install
   --path                     path    where the node data, keys and backups will be installed, defaults to $HOME/elrond
   --go-path                  path    the go path where files should be installed, will default to $GOPATH
   --display-name             name    the display name for the node
   --reinstall                        perform a clean / full reinstall (make sure you have backed up your keys before doing this!)
   --default-port             port    the default port that will be the base to start nodes from, default is 8080
   --backup-database                  backup node instance databases
   --remove-database                  removes/resets the database for node instances
   --gvm                              install go using gvm
   --go-version                       what version of golang to install, defaults to ${default_go_version}
   --install-auto-updater             install and run an auto-updater that automatically updates the git repos and compiles a new node binary when necessary
   --uninstall-auto-updater           uninstalls/removes the auto-updater
   --systemd                          use systemd for starting the node
   --update-systemd-units             if currently installed Systemd units should be reinstalled (e.g. if they've been updated in the repo)
   --tmux                             use tmux for starting the node
   --start                            if the script should start the node after the setup process has completed
   --stop                             stops all running nodes
   --auto-updater                     if the script should run in auto-updater node
   --interval                         how often the script should run while running in auto-updater mode
   --help                             print this help
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --nodes) node_count="$2" ; shift;;
  --path) elrond_path="${2%/}" ; shift;;
  --go-path) go_path="${2%/}" ; shift;;
  --display-name) display_name="$2" ; shift;;
  --reinstall) full_reinstall=true ;;
  --default-port) default_port="$2" ; shift;;
  --backup-database) backup_database=true ;;
  --remove-database) remove_database=true ;;
  --gvm) install_gvm=true ;;
  --go-version) go_version="$2" ; shift;;
  --install-auto-updater) install_auto_updater=true ;;
  --uninstall-auto-updater) uninstall_auto_updater=true ;;
  --systemd) node_mode="systemd" ;;
  --update-systemd-units) update_systemd_units=true ;;
  --tmux) node_mode="tmux" ;;
  --start) start_node=true ;;
  --stop) stop_nodes=true ;;
  --auto-updater) auto_updater=true ;;
  --interval) interval="$2" ; shift;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

set_default_option_values() {
  if [ -z "$node_count" ]; then
    identify_node_count
    
    if [ -z "$node_count" ] || (( $node_count == 0 )); then
      node_count=1
    fi
  else
    convert_to_integer "$node_count"
    node_count=$converted
  fi
  
  if [ -z "$default_port" ]; then
    default_port=8080
  else
    convert_to_integer "$default_port"
    default_port=$converted
  fi

  if [ -z "$start_node" ]; then
    start_node=false
  fi
  
  if [ -z "$stop_nodes" ]; then
    stop_nodes=false
  fi
  
  if [ -z "$install_gvm" ]; then
    install_gvm=false
  fi
  
  if [ -z "$full_reinstall" ]; then
    full_reinstall=false
  fi
  
  if [ -z "$backup_database" ]; then
    backup_database=false
  fi
  
  if [ -z "$remove_database" ]; then
    remove_database=false
  fi
  
  if [ -z "$install_auto_updater" ]; then
    install_auto_updater=false
  fi
  
  if [ -z "$uninstall_auto_updater" ]; then
    uninstall_auto_updater=false
  fi
  
  if [ -z "$update_systemd_units" ]; then
    update_systemd_units=false
  fi
  
  if [ -z "$node_mode" ]; then
    node_mode="binary"
  fi
  
  # Interval between every loop invocation
  # E.g: 30s => 30 seconds, 1m => 1 minute, 1h => 1 hour
  if [ -z "$interval" ]; then
    interval=5m
  fi
  
  if [ -z "$auto_updater" ]; then
    auto_updater=false
  fi
}

initialize() {
  set_variables
  create_base_directories
  set_state_variables
  set_default_option_values
  
  if [ "$full_reinstall" = true ]; then
    rm -rf $base_build_path && mkdir -p $base_build_path
  fi
  
  set_formatting
}

set_variables() {
  # Must be set here because of the variables that depend on it
  if [ -z "$elrond_path" ]; then
    elrond_path=$HOME/elrond
  fi
  
  if [ -z "$go_path" ]; then
    go_path=$HOME/go
  fi
  
  executing_user=$(whoami)
  configuration_files="config.toml economics.toml genesis.json nodesSetup.json p2p.toml prefs.toml server.toml"
  
  base_build_path=$go_path/src/github.com/ElrondNetwork
  node_build_path=$base_build_path/elrond-go
  node_build_binary_folder_path=$node_build_path/cmd/node
  node_build_binary_path=$node_build_binary_folder_path/node
  config_path=$base_build_path/elrond-config
  
  keys_path=$elrond_path/keys
  alternative_keys_path=$HOME
  
  tools_path=$elrond_path/tools
  nodes_path=$elrond_path/nodes
  
  if test -d $node_build_path; then
    install_method="update"
  else
    install_method="install"
  fi
}

create_base_directories() {
  mkdir -p $base_build_path
  mkdir -p $keys_path $tools_path $nodes_path
}

set_state_variables() {
  git_release_updated=false
  nodes_running=false
  nodes_already_stopped=false
  binary_compiled=false
  node_display_name_updated=false
  unset hosts
  unset tmux_sessions
  unset systemd_units
  declare -ag hosts
  declare -ag tmux_sessions
  declare -ag systemd_units
}

check_dependencies() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to run this script."
    echo "Please install it using sudo apt-get install curl"
    exit 1
  fi
  
  if ! command -v zip >/dev/null 2>&1 || ! command -v unzip >/dev/null 2>&1; then
    echo "zip and unzip are required to run this script."
    echo "Please install them using sudo apt-get install zip unzip"
    exit 1
  fi
}

#
# GENERAL
# The following methods won't run on a node-per-node basis - they only get executed once
# These functions primarily deal with making sure Go is installed and fetching the git repos in order to compile a build of the node binary
#

#
# Installation
#

set_go_version() {
  if [ -z "$go_version" ]; then
    latest_go_version=$(curl -sS https://golang.org/VERSION?m=text)
    
    if [ ! -z "$latest_go_version" ]; then
      go_version=$latest_go_version
    else
      go_version=$default_go_version
    fi
  fi
}

regular_go_installation() {
  if ! test -d /usr/local/go/bin; then
    set_go_version
  
    output_header "${header_index}. Installation - installing Go version ${go_version} using regular install"
    ((header_index++))
    
    info_message "Downloading go installation archive..."
  
    curl -LOs https://dl.google.com/go/$go_version.linux-amd64.tar.gz
    sudo tar -xzf $go_version.linux-amd64.tar.gz -C /usr/local
    rm -rf $go_version.linux-amd64.tar.gz
    
    if ! cat $HOME/.bash_profile | grep "export GOROOT" > /dev/null; then
      echo "export GOROOT=/usr/local/go" >> $HOME/.bash_profile
    fi
  
    if ! cat $HOME/.bash_profile | grep "export GOPATH" > /dev/null; then
      echo "export GOPATH=$go_path" >> $HOME/.bash_profile
    fi
  
    echo "export PATH=\$PATH:\$GOROOT/bin" >> $HOME/.bash_profile

    source $HOME/.bash_profile
  
    success_message "Go version ${go_version} successfully installed!"
    
    output_footer
  fi
}

gvm_go_installation() {
  set_go_version
  
  output_header "${header_index}. Installation - installing GVM and Go version ${go_version} using GVM"
  ((header_index++))
  
  sudo rm -rf $HOME/.gvm
  touch $HOME/.bash_profile
  
  info_message "Installing GVM"

  source <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer) 1> /dev/null 2>&1
  source $HOME/.gvm/scripts/gvm
  
  if ! cat $HOME/.bash_profile | grep ".gvm/scripts/gvm" > /dev/null; then
    echo "[[ -s "\$HOME/.gvm/scripts/gvm" ]] && source \"\$HOME/.gvm/scripts/gvm\"" >> $HOME/.bash_profile
  fi
  
  if ! cat $HOME/.bash_profile | grep "export GOPATH" > /dev/null; then
    echo "export GOPATH=$go_path" >> $HOME/.bash_profile
  fi

  source $HOME/.bash_profile
  
  success_message "GVM successfully installed!"
  
  info_message "Installing go version ${go_version}..."

  gvm install $go_version -B 1> /dev/null 2>&1
  gvm use $go_version --default 1> /dev/null 2>&1
  
  success_message "Go version ${go_version} successfully installed!"
  
  output_footer
}

source_environment_variable_scripts() {
  if test -f $HOME/.gvm/scripts/gvm; then
    source $HOME/.gvm/scripts/gvm
  fi
  
  source $HOME/.bash_profile
}

check_for_go() {
  output_header "${header_index}. Installation - verifying go is present in your system"
  ((header_index++))
  
  source_environment_variable_scripts
  
  if command -v go >/dev/null 2>&1; then
    go_version=$(go version)
    go_installation_path=$(which go)
    success_message "Successfully found go on your system!"
    success_message "Your go installation is installed in: ${go_installation_path}"
    success_message "You're running version: ${go_version}"
  else
    error_message "Can't detect go on your system! Are you sure it's properly installed?"
    exit 1
  fi
  
  output_footer
}


#
# Build/compilation
#
install_git_repos() {
  output_header "${header_index}. Build - checking if git repos elrond-go and elrond-config need to be installed or updated"
  ((header_index++))
  
  install_git_repo "go"
  binary_release_tag=$release_tag
  
  install_git_repo "config"
  
  output_footer
}

install_git_repo() {
  repo_name="elrond-${1}"
  release_tag="$(curl --silent "https://api.github.com/repos/ElrondNetwork/${repo_name}/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')"
  
  mkdir -p $base_build_path
  cd $base_build_path
  
  if test -d $repo_name; then
    cd $repo_name
    check_active_git_release
    
    if [ "$active_release_tag" != "$release_tag" ]; then
      warning_message "The script has detected that you're running an outdated release of ${repo_name} (${active_release_tag}). There's a newer version of ${repo_name} (${release_tag}) available."
      info_message "Updating git repo ${repo_name} to use the new version ${release_tag} ..."
      update_git_repo
      git_release_updated=true
    else
      success_message "You're already running the latest release of ${repo_name} (${release_tag}), there's no need to update!"
    fi
  else
    git clone https://github.com/ElrondNetwork/${repo_name} 1> /dev/null 2>&1
    cd $repo_name
    update_git_repo
    git_release_updated=true
    success_message "Successfully fetched and installed the latest ${repo_name} release ${release_tag}"
  fi
}

check_active_git_release() {
  active_release_tag="$(git describe --tags)"
}

update_git_repo() {
  git fetch 1> /dev/null 2>&1
  git checkout --force tags/${release_tag} 1> /dev/null 2>&1
  git pull 1> /dev/null 2>&1
}


#
# Configuration management
#
copy_build_configuration_files() {
  if [ -z "$matches_current_binary_version" ] || [ "$git_release_updated" = true ] || [ "$binary_compiled" = true ]; then
    output_header "${header_index}. Build - copying configuration files to build folder"
    ((header_index++))
  
    cd $node_build_path/cmd/node
    rm -rf config
    mkdir -p config
  
    cp $config_path/*.* $node_build_path/cmd/node/config
  
    if test -f $node_build_path/cmd/node/config/config.toml; then
      success_message "Successfully copied the configuration files over to ${node_build_path}/cmd/node/config"
    fi
  
    output_footer
  fi
}


#
# Compilation
#
build_version() {
  current_binary_version=$(cd ${1} && ./node --version)
}

build_binary_version() {
  build_version "${node_build_binary_folder_path}"
}

compare_build_binary_version_with_release_version() {
  build_binary_version
  matches_current_binary_version=$(echo ${current_binary_version} | grep -oam 1 -E "${binary_release_tag}")
}

compile_binaries() {
  output_header "${header_index}. Build - compiling node binary (if required)"
  ((header_index++))
  
  if test -f $node_build_binary_path; then
    compare_build_binary_version_with_release_version
    info_message "Your build binary is currently version: ${current_binary_version}."
    
    if [ -z "$matches_current_binary_version" ]; then
      warning_message "Your binary version (${current_binary_version}) isn't built using the latest released code (${binary_release_tag}). Will recompile a new binary."
      rm -rf $node_build_binary_path
    else
      success_message "Your binary is already compiled using the latest version (${binary_release_tag})!"
    fi
  fi
  
  if ! test -f $node_build_binary_path || [ "$git_release_updated" = true ]; then
    cd $node_build_path
    rm -rf $node_build_binary_path
    
    info_message "Downloading go modules..."
    GO111MODULE=on go mod vendor 1> /dev/null 2>&1
    cd cmd/node
    info_message "Compiling binaries..."
    go build -i -v -ldflags="-X main.appVersion=$(git describe --tags --long --dirty)" 1> /dev/null 2>&1
    
    compare_build_binary_version_with_release_version
    
    if [ ! -z "$matches_current_binary_version" ]; then
      success_message "Successfully compiled the node binary!"
      success_message "Your node binary is now using version ${current_binary_version} ."
      binary_compiled=true
    fi
  fi
  
  output_footer
}


#
# Systemd
#
download_and_setup_systemd_unit() {
  # File name: elrond
  local file_name=$1
  local unit_name=$file_name
  local suffix=$2
  
  if [ ! -z "$suffix" ]; then
    unit_name=$unit_name@$suffix
  fi
  
  file_name=$file_name.service
  # Unit name: elrond@8080.service
  unit_name=$unit_name.service
  
  if [ "$update_systemd_units" = true ] || ! test -f /lib/systemd/system/$unit_name; then
    output_sub_header "Systemd - installing Systemd unit"
    
    if [ "$update_systemd_units" = true ]; then
      sudo systemctl stop $unit_name 1> /dev/null 2>&1
      sudo systemctl disable $unit_name  1> /dev/null 2>&1
      sudo systemctl daemon-reload 1> /dev/null 2>&1
      sudo rm -rf /lib/systemd/system/$unit_name
    fi
  
    if ! test -f /lib/systemd/system/$unit_name; then
      cd $HOME
    
      info_message "Downloading Systemd Unit ${file_name} ..."
      rm -rf $file_name
      wget -q https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/setup/$file_name
  
      info_message "Updating ${file_name} to use correct settings"
      sed -i "s/---USER---/${executing_user}/g" $file_name
  
      if [ ! -z "$suffix" ]; then
        sed -i "s|---NODE_INSTANCE_PATH---|${node_instance_node_path}|g" $file_name
        sed -i "s/---NODE_INSTANCE_PORT---/${port_alias}/g" $file_name
        mv $file_name $unit_name
      fi
  
      info_message "Installing ${unit_name} ..."
  
      sudo rm -rf /lib/systemd/system/$unit_name
      sudo mv $unit_name /lib/systemd/system/
      sudo systemctl daemon-reload 1> /dev/null 2>&1
      sudo systemctl enable $unit_name 1> /dev/null 2>&1
  
      success_message "Successfully installed ${unit_name}!"
    fi
    
    output_sub_footer
  fi
}


#
# Tmux
#
install_tmux_if_missing() {
  if ! command -v tmux >/dev/null 2>&1; then
    sudo apt-get -y install tmux  1> /dev/null 2>&1
  fi
}

launch_tmux_session() {
  install_tmux_if_missing
  
  local session_name="$1"
  local command="$2"
  
  tmux kill-session -t "${session_name}" > /dev/null
  tmux new-session -d -s "${session_name}" > /dev/null
  tmux send -t "${session_name}" "$command" ENTER
  
  info_message "Tmux session started! Attach to the session using ${bold_text}tmux attach-session -t ${session_name}${normal_text}"
}


#
# Helpers
#
convert_to_integer() {
  converted=$((10#$1))
}

convert_index_to_port_alias() {
  if (( $node_index == 0 )); then
    port_alias=$default_port
  else
    port_alias=$((default_port + node_index))
  fi
}

#
# Auto-updater
#
install_auto_updater() {
  if [ "$install_auto_updater" = true ]; then
    output_header "${header_index}. Auto-updater - installing auto-updater"
    ((header_index++))
    
    case $node_mode in
    binary)
      error_message "If you don't want to run the auto-updater in the background using tmux or Systemd you don't have to install anything."
      error_message "Simply run the script with --auto-updater, e.g. ./setup.sh --auto-updater"
      ;;
    systemd)
      install_systemd_auto_updater
      ;;
    tmux)
      install_tmux_auto_updater
      ;;
    *)
      ;;
    esac
    
    output_footer
  fi
}

install_auto_updater_script() {
  cd $HOME
  
  mkdir -p $tools_path
  
  info_message "Downloading setup script to ${tools_path}/setup.sh"
  cd $tools_path
  curl -LOs https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/setup/setup.sh && chmod u+x setup.sh
}

install_systemd_auto_updater() {
  install_auto_updater_script
    
  download_and_setup_systemd_unit "elrond-updater"
  
  info_message "Starting the updater service..."
  sudo systemctl start elrond-updater.service
  sudo systemctl status elrond-updater.service
}

install_tmux_auto_updater() {
  install_auto_updater_script
  
  if ps aux | grep "[s]etup.sh" | grep "\-\-auto\-updater" > /dev/null; then
    info_message "Stopping previously running auto-updater..."
    for pid in `ps -ef | grep "[s]etup.sh" | grep "\-\-auto\-updater" | awk '{print $2}'`; do kill $pid; done
  fi
  
  launch_tmux_session "elrond-auto-updater" "cd $tools_path && ./setup.sh --tmux --auto-updater --interval 5m"
}

identify_node_count() {
  node_count=$(ls -1q $nodes_path | wc -l)
  info_message "Identified ${bold_text}${node_count} node(s)${normal_text} in ${bold_text}${nodes_path}${normal_text}"
}

#
# NODES
# These methods are executed on a node-per-node basis
# They primarily deal with copying the node binary and config files as well as backing up keys and config files
#

#
# Node instance management
# 
manage_nodes() {
  for ((node_index=0; node_index<=node_count-1; node_index++)); do
    manage_node
  done
}

manage_node() {
  convert_index_to_port_alias
  node_id=$((node_index+1))
  hosts+=("localhost:${port_alias}")
  
  node_instance_path=$nodes_path/$port_alias
  node_instance_node_path=$node_instance_path/node
  node_instance_node_config_path=$node_instance_path/node/config
  node_instance_backups_path=$node_instance_path/backups
  node_instance_keys_archive=$node_instance_backups_path/keys.zip
  node_instance_configs_archive=$node_instance_backups_path/configs.zip
  
  output_header "${header_index}. Node ${port_alias}: Performing actions"
  ((header_index++))
  
  create_node_directories
  use_existing_keys
  backup_keys
  compare_node_binary_version_with_release_version
  
  if ! test -f $node_instance_node_path/node || [ -z "$matches_current_binary_version" ] || [ "$git_release_updated" = true ] || [ "$binary_compiled" = true ]; then
    parse_current_display_name
    backup_node_configuration_files
    cleanup_previous_node_build
    copy_build
  fi
  
  manage_keys
  set_display_name
  install_node_systemd_unit
  
  start_node
  
  output_footer
}

create_node_directories() {
  mkdir -p $nodes_path/$port_alias/node/config
  mkdir -p $nodes_path/$port_alias/backups
}

cleanup_previous_node_build() {  
  if [ "$install_method" = "update" ] && [ "$full_reinstall" = false ]; then
    output_sub_header "Cleanup - cleaning up files from previous installation"
    
    cd $node_instance_path
    
    info_message "Removing previous compiled node binary, logs and stats directories from previous installation."
    rm -rf config node node.go logs stats
    
    if [ "$remove_database" = true ]; then
      info_message "Removing database file(s) from previous installation."
      sudo rm -rf db
    fi
    
    output_sub_footer
  fi
}

copy_build() {
  output_sub_header "Build - copying build to ${node_instance_path}/node"

  cd $node_build_path/cmd/node
  mkdir -p $node_instance_path/node

  if [ "$git_release_updated" = true ] || [ "$binary_compiled" = true ]; then
    rm -rf $node_instance_path/node/node $node_instance_path/node/config
    cp -R config/ node $node_instance_path/node
  else
    if ! test -f $node_instance_path/node/node; then
      cp node $node_instance_path/node
    fi
  
    if ! test -d $node_instance_node_config_path; then
      cp -R config/ $node_instance_path/node
    fi
  fi
  
  if test -f $node_instance_path/node/node && test -d $node_instance_node_config_path; then
    success_message "Successfully copied node binary and config files to ${node_instance_path}/node"
    set_display_name
  fi
  
  output_sub_footer
}

#
# Configuration management
#
backup_node_configuration_files() {
  local archive_name="configs.zip"
  
  if ls -d $node_instance_node_path/config/*.toml 1> /dev/null 2>&1; then
    output_sub_header "Configuration - backing up existing configuration files"
    
    rm -rf $node_instance_configs_archive
    
    info_message "Backing up existing configuration files from ${node_instance_path}/node/config to ${node_instance_path}/backups/configs.zip ..."
    
    cd $node_instance_node_path/config
    
    zip -qj ${archive_name} ${configuration_files}
    mv ${archive_name} $node_instance_path/backups/
    
    if test -f $node_instance_path/backups/configs.zip; then
      success_message "Successfully backed up previous configuration files to ${node_instance_path}/backups/configs.zip!"
    fi
    
    output_sub_footer
  fi
}

set_display_name() {
  if [ ! -z "$display_name" ]; then
    generate_node_display_name
    update_node_display_name "${node_display_name}"
  else
    if [ ! -z "$current_display_name" ]; then
      update_node_display_name "${current_display_name}"
    fi
  fi
}

generate_node_display_name() {
  if (( node_count > 1 )); then
    node_display_name=$display_name-$node_id
  else
    node_display_name=$display_name
  fi
}

update_node_display_name() {
  sed -i "s/NodeDisplayName = \"[^\"]*\"/NodeDisplayName = \"${1}\"/g" $node_instance_node_config_path/prefs.toml
  node_display_name_updated=true
}

parse_current_display_name() {
  if [ "$install_method" = "update" ] && test -f $node_instance_node_config_path/prefs.toml; then
    current_display_name=$(cat $node_instance_node_config_path/prefs.toml | grep -oam 1 "NodeDisplayName = \"[^\"]*\"" | grep -oam 1 "\"[^\"]*\"" | tr -d '"')
  fi
}

#
# Compilation
#
node_binary_version() {
  build_version="${node_instance_node_path}"
}

compare_node_binary_version_with_release_version() {
  node_binary_version
  matches_current_binary_version=$(echo ${current_binary_version} | grep -oam 1 -E "${binary_release_tag}")
}

#
# Key management
#
use_existing_keys() {
  # Try to first see if the keys have been placed in the keys folder, e.g. $HOME/elrond/keys/keys-8080.zip
  if test -f $keys_path/keys-$port_alias.zip; then
    cp $keys_path/keys-$port_alias.zip $node_instance_keys_archive
  # Or try to look for them, in the home folder, e.g: $HOME/keys-8080.zip
  elif test -f $alternative_keys_path/keys-$port_alias.zip; then
    cp $alternative_keys_path/keys-$port_alias.zip $node_instance_keys_archive
  fi
}

backup_keys() {  
  if ! test -f $node_instance_keys_archive && ls -d $node_instance_node_path/config/*.pem 1> /dev/null 2>&1; then
    output_sub_header "Keys - backing up keys"
    
    info_message "Backing up keys from ${node_instance_node_path}/config to ${node_instance_keys_archive}..."
    
    cd $node_instance_node_path/config
    zip -qj keys-$port_alias.zip *.pem
    mv keys-$port_alias.zip $node_instance_backups_path
    
    if test -f $node_instance_keys_archive; then
      success_message "Successfully backed up keys to ${node_instance_keys_archive}!"
    fi
    
    output_sub_footer
  fi
}

generate_keys() {
  if ! test -f $node_instance_keys_archive && ! ls -d $node_instance_node_path/config/*.pem  1> /dev/null 2>&1; then
    output_sub_header "Keys - generating new keys"
    
    info_message "Generating new keys..."
    
    cd $node_build_path/cmd/keygenerator
    go build 1> /dev/null 2>&1
    ./keygenerator 1> /dev/null 2>&1
    
    declare -a pemfiles=("initialBalancesSk.pem" "initialNodesSk.pem")
    
    for pemfile in "${pemfiles[@]}"; do
      if test -f $pemfile; then
        echo ""
        success_message "Successfully generated ${pemfile}!"
        cp $pemfile $node_instance_node_path/config/
      
        if test -f $node_instance_node_path/config/$pemfile; then
          success_message "Successfully copied ${pemfile} to ${node_instance_node_path}/config/${pemfile}!"
        fi
      fi
    done
  
    output_sub_footer
  fi
  
  backup_keys
}

copy_keys() {  
  if test -f $node_instance_keys_archive && ! ls -d $node_instance_node_path/config/*.pem 1> /dev/null 2>&1; then
    output_sub_header "Keys - copying existing keys"
  
    cp $node_instance_keys_archive $node_instance_node_path/config/
    cd $node_instance_node_path/config
    unzip -qj *.zip
    rm -rf *.zip
  
    success_message "Successfully copied existing keys from ${node_instance_keys_archive} to ${node_instance_node_path}/config"
  
    output_sub_footer
  fi
}

manage_keys() {
  generate_keys
  copy_keys
}

#
# Systemd: node specific
#
install_node_systemd_unit() {
  if [ "$node_mode" = "systemd" ]; then
    download_and_setup_systemd_unit "elrond" "${port_alias}"
  fi
}


#
# Startup methods
#
start_node() {
  if [ "$start_node" = true ]; then
    output_sub_header "Start - starting node"
    
    case $node_mode in
    binary)
      start_node_using_regular_binary
      ;;
    systemd)
      start_node_using_systemd
      ;;
    tmux)
      start_node_using_tmux
      ;;
    *)
      ;;
    esac
    
    output_sub_footer
  fi
}

start_node_using_regular_binary() {
  stop_nodes
  
  if (( node_count > 1 )); then
    error_message "You can only start one node at a time in the normal boot mode."
    error_message "Use --tmux or --systemd to start multiple nodes at once."
    error_message "You can also start this specific node instance in a separate session/window using cd ${node_instance_node_path} && ./node"
  else
    info_message "Starting node using regular binary..."
    cd $node_instance_node_path && ./node
  fi
}

start_node_using_systemd() {
  local service_name=elrond@$port_alias.service
  
  info_message "Potentially starting/restarting node using Systemd unit ${service_name}..."
  
  if test -f /lib/systemd/system/$service_name; then
    already_started=$(systemctl is-active $service_name)
    
    if ! systemctl is-active --quiet $service_name || [ "$git_release_updated" = true ] || [ "$binary_compiled" = true ] || [ "$node_display_name_updated" = true ]; then
      sudo systemctl stop $service_name
      sudo systemctl start $service_name
      
      if systemctl is-active --quiet $service_name; then
        success_message "Successfully started node using Systemd unit ${service_name}!"
      fi
    else
      info_message "Node doesn't have to be restarted right now - no changes have occurred."
    fi
    
    echo ""
    info_message "Current status for ${service_name}:"
    sudo systemctl status $service_name
    
    systemd_units+=("$service_name")
  else
    error_message "Couldn't find the systemd unit file in /lib/systemd/system/${service_name} - please install it by re-running this script using the --install-systemd argument."
  fi
}

start_node_using_tmux() {
  stop_nodes
  local tmux_session_name="elrond-${port_alias}"
  
  launch_tmux_session "${tmux_session_name}" "cd ${node_instance_node_path} && ./node"
  tmux_sessions+=("${tmux_session_name}")
}

check_for_running_nodes() {
  if ps aux | grep "[n]ode" > /dev/null; then
    nodes_running=true
  fi
}

stop_nodes() {
  check_for_running_nodes
  
  if [ "$nodes_running" = true ] && [ "$nodes_already_stopped" = false ]; then
    info_message "Stopping node(s)..."
    for pid in `ps -ef | grep "[n]ode" | awk '{print $2}'`; do kill $pid; done
    nodes_already_stopped=true
  fi
}

display_node_summary() {
  output_header "${header_index}. Node summary:"
  ((header_index++))
  
  if (( ${#hosts[@]} )); then
    info_message "${bold_text}Installed/active nodes on your system:${normal_text}"
    
    for host in "${hosts[@]}"; do
    	info_message "${host}"
    done
  fi
  
  if (( ${#tmux_sessions[@]} )); then
    echo ""
    info_message "${bold_text}Active tmux sessions:${normal_text}"
    
    for tmux_session in "${tmux_sessions[@]}"; do
    	info_message "${tmux_session} - attach to the session using ${bold_text}tmux attach-session -t ${tmux_session}${normal_text}"
    done
  fi
  
  if (( ${#systemd_units[@]} )); then
    echo
    info_message "${bold_text}Your installed Systemd units:${normal_text}"
    echo 
    
    for systemd_unit in "${systemd_units[@]}"; do
    	info_message "${bold_text}${systemd_unit}${normal_text}"
      info_message "Manage the node via Systemd using the following commands:"
      info_message "\tstart: ${bold_text}sudo systemctl start ${systemd_unit}${normal_text}"
      info_message "\tstop: ${bold_text}sudo systemctl stop ${systemd_unit}${normal_text}"
      info_message "\trestart: ${bold_text}sudo systemctl restart ${systemd_unit}${normal_text}"
      info_message "\tstatus: ${bold_text}sudo systemctl status ${systemd_unit}${normal_text}"
      echo
    done
  fi
  
  output_footer
}


#
# Formatting/outputting methods
#
set_formatting() {
  header_index=1
  
  bold_text=$(tput bold)
  italic_text=$(tput sitm)
  normal_text=$(tput sgr0)
  black_text=$(tput setaf 0)
  red_text=$(tput setaf 1)
  green_text=$(tput setaf 2)
  yellow_text=$(tput setaf 3)
}

info_message() {
  echo -e "${1}"
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

output_separator() {
  echo "------------------------------------------------------------------------"
}

output_banner() {
  output_header "Running Elrond: Battle of Nodes installer/updater v${version}"
  current_time=`date`
  
  if [ "$auto_updater" = true ]; then
    mode_text="auto-updater"
  else
    mode_text="normal"
  fi
  
  info_message "You're running ${bold_text}${script_name}${normal_text} as ${bold_text}${executing_user}${normal_text} in ${bold_text}${mode_text}${normal_text} mode. Current time is: ${bold_text}${current_time}${normal_text}."
}

output_header() {
  echo
  output_separator
  echo "${bold_text}${1}${normal_text}"
  output_separator
  echo
}

output_sub_header() {
  echo "${italic_text}${1}${normal_text}:"
}

output_footer() {
  echo
  output_separator
}

output_sub_footer() {
  echo
}


#
# Main setup function
#
run_setup() {
  initialize
  
  output_banner
  
  check_dependencies
  
  if [ "$install_auto_updater" = true ]; then
    error_message "You need to run --install-auto-updater together with the --auto-updater parameter, e.g: ./setup.sh --auto-updater --install-auto-updater"
    exit 0
  fi
  
  if [ "$stop_nodes" = true ]; then
    stop_nodes
    info_message "Stopped nodes!"
    exit 0
  fi
    
  # General methods
  if [ "$install_gvm" = true ]; then
    gvm_go_installation
  else
    regular_go_installation
  fi
  
  check_for_go
  
  # Builds the actual node software
  install_git_repos
  compile_binaries
  copy_build_configuration_files
  
  # Copies the node software, configuration etc. and sets up the number of requested nodes
  manage_nodes
  
  display_node_summary
}

#
# Main auto-updater functionality
#
run_auto_updater() {
  if [ "$install_auto_updater" = true ]; then
    initialize
    output_banner
    install_auto_updater
    exit 0
  else
    run_setup
  fi
  
  # Reset state variables for next run
  set_state_variables
}

#
# Run the script
#
run() {
  if [ "$auto_updater" = true ]; then
    while [ true ]; do # Run in an infinite loop
      run_auto_updater
      echo ""
      info_message "Waiting ${interval} before the next auto-updater check..."
      sleep $interval
    done
  else
    run_setup
  fi
}

run
