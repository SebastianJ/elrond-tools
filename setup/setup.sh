#!/bin/bash
version="0.0.1"
script_name="setup.sh"
default_go_version="go1.13.1"

#
# Arguments/configuration
# 
usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   --go-path        path  the go path where files should be installed, will default to $GOPATH
   --display-name   name  the display name for the node
   --reinstall            perform a clean / full reinstall (make sure you have backed up your keys before doing this!)
   --reset-database       resets the database for an existing installation
   --gvm                  force installation/reinstallation of gvm and go
   --go-version           what version of golang to install, defaults to ${default_go_version}
   --install-systemd      install a systemd unit to manage the node process
   --install-updater      install a systemd unit for the auto-updater
   --systemd              use systemd for starting the node
   --tmux                 use tmux for starting the node
   --start                if the script should start the node after the setup process has completed
   --daemonize            if the script should daemonize itself / run in an endless loop
   --interval             how often the script should run while daemonized / running in the endless loop
   --help                 print this help
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --go-path) go_path="${2%/}" ; shift;;
  --display-name) display_name="$2" ; shift;;
  --reinstall) full_reinstall=true ;;
  --reset-database) reset_database=true ;;
  --gvm) install_gvm=true ;;
  --go-version) go_version="$2" ; shift;;
  --install-systemd) install_systemd_unit=true ;;
  --install-updater) install_updater_systemd_unit=true ;;
  --systemd) node_mode="systemd" ;;
  --tmux) node_mode="tmux" ;;
  --start) start_node=true ;;
  --daemonize) daemonize=true ;;
  --interval) interval="$2" ; shift;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

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
  
  if [ -z "$full_reinstall" ]; then
    full_reinstall=false
  fi
  
  if [ -z "$reset_database" ]; then
    reset_database=false
  fi
  
  if [ -z "$install_systemd_unit" ]; then
    install_systemd_unit=false
  fi
  
  if [ -z "$install_updater_systemd_unit" ]; then
    install_updater_systemd_unit=false
  fi
  
  if [ -z "$go_version" ]; then
    go_version=$default_go_version
  fi
  
  if [ -z "$node_mode" ]; then
    node_mode="binary"
  fi
  
  # Interval between every loop invocation
  # E.g: 30s => 30 seconds, 1m => 1 minute, 1h => 1 hour
  if [ -z "$interval" ]; then
    interval=1m
  fi
  
  if [ -z "$daemonize" ]; then
    daemonize=false
  fi
}

initialize() {
  executing_user=$(whoami)
  set_default_option_values
  set_variables
  
  if [ "$full_reinstall" = true ]; then
    rm -rf $base_path && mkdir -p $base_path
  fi
  
  set_formatting
}

set_variables() {
  base_path=$go_path/src/github.com/ElrondNetwork
  node_path=$base_path/elrond-go
  config_path=$base_path/elrond-config
  tools_path=$HOME/elrond-tools
  
  keys_archive=$HOME/keys.tar.gz
  configs_archive=$HOME/configs.tar.gz
  
  configuration_files="config.toml economics.toml genesis.json	nodesSetup.json	p2p.toml server.toml"
  git_release_updated=false
  nodes_running=false
  
  if test -d $node_path; then
    install_method="update"
  else
    install_method="install"
    install_gvm=true
  fi
  
  mkdir -p $base_path
}

#
# Installation
# 
gvm_installation() {
  if [ "$install_gvm" = true ]; then
    output_header "${header_index}. Installation - installing GVM and Go version ${go_version}"
    ((header_index++))
    
    sudo rm -rf $HOME/.gvm
    touch $HOME/.bash_profile
    
    info_message "Installing GVM"

    source <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer) 1> /dev/null 2>&1

    source $HOME/.gvm/scripts/gvm
    
    if ! cat $HOME/.bash_profile | grep ".gvm/scripts/gvm" > /dev/null; then
      echo "[[ -s "$HOME/.gvm/scripts/gvm" ]] && source \"$HOME/.gvm/scripts/gvm\"" >> $HOME/.bash_profile
    fi
    
    if ! cat $HOME/.bash_profile | grep "export GOPATH" > /dev/null; then
      echo "export GOPATH=$go_path" >> $HOME/.bash_profile
    fi
    
    if ! cat $HOME/.bash_profile | grep "export PATH" > /dev/null; then
      echo "export PATH=\"\$PATH:${go_path}/bin\"" >> $HOME/.bash_profile
    fi

    source $HOME/.bash_profile
    
    export GOPATH=$go_path
    export PATH="$PATH:${go_path}/bin"
    
    success_message "GVM successfully installed!"
    
    info_message "Installing go version ${go_version}..."

    gvm install $go_version -B 1> /dev/null 2>&1
    gvm use $go_version --default 1> /dev/null 2>&1
    
    success_message "Go version ${go_version} successfully installed!"
    
    output_footer
  fi
}

install_git_repos() {
  output_header "${header_index}. Installation - installing/updating git repos elrond-go and elrond-config"
  ((header_index++))
  
  install_git_repo "go"
  install_git_repo "config"
  
  output_footer
}

install_git_repo() {
  repo_name="elrond-${1}"
  release_tag="$(curl --silent "https://api.github.com/repos/ElrondNetwork/${repo_name}/releases/latest" | grep -Po '"tag_name": "\K.*?(?=")')"
  
  mkdir -p $base_path
  cd $base_path
  
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

backup_configuration_files() {
  if ls -d ${node_path}/cmd/node/config/*.toml 1> /dev/null 2>&1; then
    output_header "${header_index}. Configuration - backing up existing configuration files"
    ((header_index++))
    
    rm -rf $configs_archive
    
    info_message "Backing up existing configuration files from ${node_path}/cmd/node/config to ${configs_archive}..."
    
    local archive_name="configs.tar.gz"
    
    cd $node_path/cmd/node/config
    tar -czvf ${archive_name} ${configuration_files} 1> /dev/null 2>&1
    mv ${archive_name} $HOME
    
    if test -f $configs_archive; then
      success_message "Successfully backed up previous configuration files to ${configs_archive}!"
    fi
    
    output_footer
  fi
}

copy_configuration_files() {
  output_header "${header_index}. Configuration - copying configuration files"
  ((header_index++))
  
  cd $node_path/cmd/node/config
  rm -rf $configuration_files
  
  cp $config_path/*.* $node_path/cmd/node/config
  
  if test -f $node_path/cmd/node/config/config.toml; then
    success_message "Successfully copied the configuration files over to ${node_path}/cmd/node/config"
  fi
  
  output_footer
}

update_display_name() {
  if [ ! -z "$display_name" ]; then
    sed -i "s/NodeDisplayName = \"[a-zA-Z0-9]*\"/NodeDisplayName = \"${display_name}\"/g" $node_path/cmd/node/config/config.toml
  fi
}

#
# Compilation
#

compile_binaries() {
  output_header "${header_index}. Compilation - compiling node binary"
  ((header_index++))
  
  cd $node_path
  info_message "Downloading go modules"
  GO111MODULE=on go mod vendor 1> /dev/null 2>&1
  cd cmd/node
  info_message "Compiling binaries..."
  go build -i -v -ldflags="-X main.appVersion=$(git describe --tags --long --dirty)" 1> /dev/null 2>&1
  success_message "Successfully compiled the binaries!"
  
  output_footer
}


#
# Key management
# 
backup_keys() {
  if ! test -f $keys_archive && ls -d ${node_path}/cmd/node/config/*.pem 1> /dev/null 2>&1; then
    output_header "${header_index}. Keys - backing up keys"
    ((header_index++))
    
    info_message "Backing up keys from ${node_path}/cmd/node/config to ${keys_archive}..."
    
    cd $node_path/cmd/node/config
    tar -czvf keys.tar.gz *.pem 1> /dev/null 2>&1
    mv keys.tar.gz $HOME
    
    if test -f $keys_archive; then
      success_message "Successfully backed up keys to ${keys_archive}!"
    fi
    
    output_footer
  fi
}

generate_keys() {
  if ! test -f $keys_archive && ! ls -d ${node_path}/cmd/node/config/*.pem 1> /dev/null 2>&1; then
    output_header "${header_index}. Keys - generating new keys"
    ((header_index++))
    
    info_message "Generating new keys..."
    
    cd $node_path/cmd/keygenerator
    go build 1> /dev/null 2>&1
    ./keygenerator 1> /dev/null 2>&1
    
    if test -f initialBalancesSk.pem; then
      echo ""
      success_message "Successfully generated initialBalancesSk.pem!"
      cp initialBalancesSk.pem $node_path/cmd/node/config
      
      if test -f $node_path/cmd/node/config/initialBalancesSk.pem; then
        success_message "Successfully copied initialBalancesSk.pem to $node_path/cmd/node/config/initialBalancesSk.pem!"
      fi
    fi
  
    if test -f initialNodesSk.pem; then
      echo ""
      success_message "Successfully generated initialNodesSk.pem!"
      cp initialNodesSk.pem $node_path/cmd/node/config
      
      if test -f $node_path/cmd/node/config/initialNodesSk.pem; then
        success_message "Successfully copied initialNodesSk.pem to $node_path/cmd/node/config/initialNodesSk.pem!"
      fi
    fi
  
    output_footer
  fi
  
  backup_keys
}

copy_keys() {
  if test -f $keys_archive && ! ls -d ${node_path}/cmd/node/config/*.pem 1> /dev/null 2>&1; then
    output_header "${header_index}. Keys - copying existing keys"
    ((header_index++))
  
    cp $keys_archive $node_path/cmd/node/config
    cd $node_path/cmd/node/config
    tar -xzvf *.tar.gz 1> /dev/null 2>&1
    rm -rf *.tar.gz
  
    success_message "Successfully copied existing keys from ${keys_archive} to ${node_path}/cmd/node/config"
  
    output_footer
  fi
}

manage_keys() {
  generate_keys
  copy_keys
}


#
# Misc 
#
cleanup() {
  if [ "$install_method" = "update" ] && [ "$full_reinstall" = false ]; then
    output_header "${header_index}. Cleanup - cleaning up files from previous installation"
    ((header_index++))
    
    cd $node_path/cmd/node/config
    
    info_message "Removing logs and stats directories from previous installation."
    
    sudo rm -rf logs stats
    
    if [ "$reset_database" = true ]; then
      info_message "Removing database file(s) from previous installation."
      sudo rm -rf db
    fi
    
    output_footer
  fi
}

#
# Systemd
# 
install_systemd_unit() {
  if [ "$install_systemd_unit" = true ]; then
    output_header "${header_index}. Systemd - installing Systemd unit"
    ((header_index++))
    
    download_and_setup_systemd_unit "elrond.service"
    
    output_footer
  fi
}

install_updater_systemd_unit() {
  if [ "$install_updater_systemd_unit" = true ]; then
    output_header "${header_index}. Systemd - installing Updater Systemd unit"
    ((header_index++))
    
    cd $HOME
    
    mkdir -p $tools_path
    rm -rf $tools_path/setup.sh
    
    info_message "Downloading setup script to ${tools_path}/setup.sh"
    cd $tools_path
    wget -q https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/setup/setup.sh
    chmod u+x setup.sh
    
    download_and_setup_systemd_unit "elrond-updater.service"
    
    info_message "Starting the updater service..."
    sudo systemctl start elrond-updater.service
    sudo systemctl status elrond-updater.service
    
    output_footer
  fi
}

download_and_setup_systemd_unit() {
  local unit_name=$1
  
  cd $HOME
  
  sudo systemctl stop $unit_name 1> /dev/null 2>&1
  sudo systemctl disable $unit_name  1> /dev/null 2>&1
  sudo systemctl daemon-reload 1> /dev/null 2>&1
  
  info_message "Downloading Updater ${unit_name} ..."
  sudo rm -rf /lib/systemd/system/$unit_name
  wget -q https://raw.githubusercontent.com/SebastianJ/elrond-tools/master/systemd/$unit_name
  
  info_message "Updating ${unit_name} to use correct settings"
  sed -i "s/---USER---/${executing_user}/g" $unit_name
  
  info_message "Installing ${unit_name} ..."
  sudo mv $unit_name /lib/systemd/system/
  sudo systemctl daemon-reload 1> /dev/null 2>&1
  sudo systemctl enable $unit_name 1> /dev/null 2>&1
  
  success_message "Successfully installed ${unit_name}!"
}

#
# Startup methods
#
start_node() {
  check_for_running_nodes
  
  if [ "$start_node" = true ] && ([ "$git_release_updated" = true ] || [ "$nodes_running" = false ]); then
    output_header "${header_index}. Node - starting node"
    ((header_index++))
    
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
    
    output_footer
  fi
}

start_node_using_regular_binary() {
  info_message "Starting node using regular binary..."
  
  stop_nodes
  
  cd $node_path/cmd/node/ && ./node
}

start_node_using_systemd() {
  info_message "Starting node using Systemd..."
  
  if test -f /lib/systemd/system/elrond.service; then
    sudo systemctl stop elrond.service
    sudo systemctl start elrond.service
    sudo systemctl status elrond.service
  else
    error_message "Couldn't find the systemd unit file in /lib/systemd/system/elrond.service - please install it by re-running this script using the --install-systemd argument."
  fi
}

start_node_using_tmux() {
  if ! command -v tmux >/dev/null 2>&1; then
    sudo apt-get -y install tmux  1> /dev/null 2>&1
  fi
  
  stop_nodes
  
  info_message "Starting node using tmux..."
  
  tmux_session_name="elrond"
  tmux kill-session -t "${tmux_session_name}"
  tmux new-session -d -s "${tmux_session_name}"
  tmux send -t "${tmux_session_name}" "cd ${node_path}/cmd/node && ./node" ENTER
  
  info_message "Tmux session started! Attach to the session using ${bold_text}tmux attach-session -t ${tmux_session_name}${normal_text}"
}

check_for_running_nodes() {
  if ps aux | grep '[n]ode' > /dev/null; then
    nodes_running=true
  fi
}

stop_nodes() {
  if [ "$nodes_running" = true ]; then
    info_message "Stopping node(s)..."
    for pid in `ps -ef | grep "[n]ode" | awk '{print $2}'`; do kill $pid; done
  fi
}

#
# Formatting/outputting methods
#
set_formatting() {
  header_index=1
  
  bold_text=$(tput bold)
  normal_text=$(tput sgr0)
  black_text=$(tput setaf 0)
  red_text=$(tput setaf 1)
  green_text=$(tput setaf 2)
  yellow_text=$(tput setaf 3)
}

info_message() {
  echo ${1}
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
  output_header "Running Elrond: Battle of Nodes installer v${version}"
  current_time=`date`
  echo "You're running ${bold_text}${script_name}${normal_text} as ${bold_text}${executing_user}${normal_text}. Current time is: ${bold_text}${current_time}${normal_text}."
}

output_header() {
  echo
  output_separator
  echo "${bold_text}${1}${normal_text}"
  output_separator
  echo
}

output_footer() {
  echo
  output_separator
}

#
# Main script function
#
perform_setup() {
  initialize
  
  output_banner
  
  gvm_installation
  backup_keys
  
  install_git_repos
  
  if [ "$git_release_updated" = true ]; then
    backup_configuration_files
    copy_configuration_files
    compile_binaries
    manage_keys
    cleanup
  fi
  
  update_display_name
  
  install_systemd_unit
  install_updater_systemd_unit
  
  start_node
}


#
# Run the script
#
run() {
  if [ "$daemonize" = true ]; then
    if [ "$node_mode" = "systemd" ] || [ "$node_mode" = "tmux" ]; then
      # Run in an infinite loop
      while [ 1 ]
      do
        perform_setup
        echo ""
        info_message "Waiting ${interval} before the next update check..."
        sleep $interval
      done
    else
      error_message "Unfortunately the daemonization mode only supports starting/restarting the node using systemd (--systemd) or tmux (--tmux). Use any of those options and run the script again."
    fi

  else
    perform_setup
  fi
}

run
