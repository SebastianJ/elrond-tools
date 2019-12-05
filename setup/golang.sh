#!/bin/bash
version="0.0.1"
script_name="golang.sh"
default_go_version="go1.13.4"

#
# Arguments/configuration
#
usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   --use-gvm                          install go using gvm
   --go-path        path              the go path where files should be installed, will default to $GOPATH
   --version        version           what version of golang to install, defaults to ${default_go_version}
   --help                             print this help
EOT
}

while [ $# -gt 0 ]; do
  case $1 in
  --use-gvm) install_using_gvm=true ;;
  --go-path) go_path="${2%/}" ; shift;;
  --version) go_version="$2" ; shift;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

set_variables() {  
  if [ -z "$install_using_gvm" ]; then
    install_using_gvm=false
  fi
  
  if [ -z "$go_path" ]; then
    go_path=$HOME/go
  fi
  
  profile_file=".bash_profile"
}

initialize() {
  set_variables
  set_formatting
}

install_go() {
  output_header "${header_index}. Installation - verifying go is present in your system"
  ((header_index++))
  
  source_environment_variable_scripts
  
  if command -v go >/dev/null 2>&1 || test -d /usr/local/go/bin; then
    detected_go_version=$(go version)
    detected_go_installation_path=$(which go)
    success_message "Successfully found go on your system!"
    success_message "Your go installation is installed in: ${detected_go_installation_path}"
    success_message "You're running version: ${detected_go_version}"
  else
    info_message "Can't detect go on your system! Proceeding to install..."
    
    set_go_version
    
    if [ "$install_using_gvm" = true ]; then
      gvm_go_installation
    else
      regular_go_installation
    fi
    
    source_environment_variable_scripts
  fi
  
  output_footer
}

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
    output_header "${header_index}. Installation - installing Go version ${go_version} using regular install"
    ((header_index++))
    
    info_message "Downloading go installation archive..."
  
    curl -LOs https://dl.google.com/go/$go_version.linux-amd64.tar.gz
    sudo tar -xzf $go_version.linux-amd64.tar.gz -C /usr/local
    rm -rf $go_version.linux-amd64.tar.gz
    
    touch $HOME/$profile_file
    
    if ! cat $HOME/$profile_file | grep "export GOROOT" > /dev/null; then
      echo "export GOROOT=/usr/local/go" >> $HOME/$profile_file
    fi
  
    if ! cat $HOME/$profile_file | grep "export GOPATH" > /dev/null; then
      echo "export GOPATH=$go_path" >> $HOME/$profile_file
    fi
  
    echo "export PATH=\$PATH:\$GOROOT/bin" >> $HOME/$profile_file

    source $HOME/$profile_file
  
    success_message "Go version ${go_version} successfully installed!"
    
    output_footer
  fi
}

gvm_go_installation() {
  output_header "${header_index}. Installation - installing GVM and Go version ${go_version} using GVM"
  ((header_index++))
  
  sudo rm -rf $HOME/.gvm
  touch $HOME/$profile_file
  
  info_message "Installing GVM"

  source <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer) 1> /dev/null 2>&1
  source $HOME/.gvm/scripts/gvm
  
  if ! cat $HOME/$profile_file | grep ".gvm/scripts/gvm" > /dev/null; then
    echo "[[ -s "\$HOME/.gvm/scripts/gvm" ]] && source \"\$HOME/.gvm/scripts/gvm\"" >> $HOME/$profile_file
  fi
  
  if ! cat $HOME/$profile_file | grep "export GOPATH" > /dev/null; then
    echo "export GOPATH=$go_path" >> $HOME/$profile_file
  fi

  source $HOME/$profile_file
  
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
  
  if test -f $HOME/$profile_file; then
    source $HOME/$profile_file
  fi
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
  output_header "Running Golang installer v${version}"
  current_time=`date`
  info_message "You're running ${bold_text}${script_name}${normal_text} as ${bold_text}${executing_user}${normal_text}. Current time is: ${bold_text}${current_time}${normal_text}."
  echo
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

install() {
  initialize
  install_go
}

install
