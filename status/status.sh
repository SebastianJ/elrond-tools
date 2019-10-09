#!/bin/bash

# Author: Sebastian Johnsson - https://github.com/SebastianJ

version="0.0.1"
script_name="status.sh"

#
# Arguments/configuration
# 
usage() {
   cat << EOT
Usage: $0 [option] command
Options:
   --hosts          hosts   a comma separated/delimited list of hosts you want to check status for. E.g: --hosts localhost:8080,localhost:8081,localhost:8082
   --compact                compact output, skipping some unnecessary data
   --no-formatting          disable formatting (colors, bold text etc.), recommended when using the script output in emails etc.
   --debug                  debug mode, output original response etc.
   --help                   print this help
EOT
}

while [ $# -gt 0 ]
do
  case $1 in
  --hosts) hosts_string="${2}" ; shift;;
  --compact) compact_mode=true;;
  --no-formatting) format_output=false;;
  --debug) debug_mode=true;;
  -h|--help) usage; exit 1;;
  (--) shift; break;;
  (-*) usage; exit 1;;
  (*) break;;
  esac
  shift
done

set_default_option_values() {
  default_port=8080
  
  if [ -z "$compact_mode" ]; then
    compact_mode=false
  fi
  
  if [ -z "$format_output" ]; then
    format_output=true
  fi
  
  if [ -z "$debug_mode" ]; then
    debug_mode=false
  fi
}

check_dependencies() {
  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to run this script."
    echo "Please install it using sudo apt-get install curl"
    exit 1
  fi
  
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required to run this script."
    echo "Please install it using sudo apt-get install jq"
    exit 1
  fi
}

initialize() {
  check_dependencies
  set_default_option_values
  executing_user=$(whoami)
  set_formatting
}

#
# Check hosts
#

parse_hosts() {
  if [ -z "$hosts_string" ]; then
    identify_node_processes
  else
    hosts_string="$(echo -e "${hosts_string}" | tr -d '[:space:]')"
    hosts=($(echo "${hosts_string}" | tr ',' '\n'))
  fi
  
  if [ -z "$hosts" ] || [ ${#hosts[@]} -eq 0 ]; then
    echo ""
    error_message "You didn't supply any hosts to check, neither could the script identify any running node processes on your computer/server. Please provide hosts using the --hosts parameter"
    echo ""
    exit 1
  fi
}

identify_node_processes() {
  # Need to pass -g in order to make the hosts variable global - otherwise it's locally scoped to this function
  declare -ag hosts
  ports=($(ps aux | grep "[n]ode --rest-api-port" | grep -Po "\-\-rest-api-port (\d+)" | grep -Po "\d+"))
  
  if [ ${#ports[@]} -eq 0 ]; then
    if ps aux | grep '[n]ode' > /dev/null; then
      hosts+=("localhost:${default_port}")
    fi
  else
    for port in ${ports[@]}; do
      hosts+=("localhost:${port}")
    done
  fi
}

check_hosts() {
  for host in "${hosts[@]}"
  do
    check_host "${host}"
  done
}

check_host() {
  local host=$1
  
  # Add the default port (8080) to hosts missing the port component
  if [[ ! $host =~ :[0-9]{4}$ ]]; then
    host="${host}:${default_port}"
  fi
  
  output_header "${header_index}. Checking host ${host}"
  ((header_index++))
  
  local response=$(curl --silent http://${host}/node/status | jq '.details')
    
  if [ ! -z "$response" ]; then    
    if [ "$debug_mode" = true ]; then
      echo ""
      echo "Response: ${response}"
      echo ""
    fi
    
    parse_variables_from_json
    
    echo "${bold_text}Instance info:${normal_text}"
    output_data "Node type" "${node_type}"
    output_data "App version" "${app_version}"
    
    echo ""
    echo "${bold_text}Consensus info:${normal_text}"
    
    if [ "$consensus_state" = "participant" ]; then
      success_message "${italic_text}Consensus state:${normal_text}${green_text} ${bold_text}${consensus_state}${normal_text}"
    else
      output_data "Consensus state" "${consensus_state}"
    fi
    
    output_data "Consensus group participation count" "${count_consensus}"
    output_data "Elected consensus leader count" "${count_leader}"
    output_data "Consensus proposed & accepted blocks" "${count_accepted_blocks}"
    
    echo ""
    echo "${bold_text}Block info:${normal_text}"
    output_data "Current block height" "${current_round}"
    
    if [ "$compact_mode" = false ]; then
      output_data "Current block size" "${current_block_size}"
      output_data "Current block hash" "${current_block_hash}"
      output_data "Current round timestamp" "${current_round_timestamp}"
    fi
    
    echo ""
    echo "${bold_text}Chain/Network info:${normal_text}"
    
    if [ "$is_syncing" = "0" ]; then
      success_message "${italic_text}Status:${normal_text}${green_text} ${bold_text}synchronized${normal_text}"
    else
      warning_message "${italic_text}Status:${normal_text}${yellow_text} ${bold_text}synchronizing${normal_text}"
    fi
    
    if [ "$compact_mode" = false ]; then
      if [ ! -z "$tx_pool_load" ] && [ ! "$tx_pool_load" = "null" ]; then
        output_data "Number of transactions in pool" "${tx_pool_load}"
      fi
    
      output_data "Number of transactions processed" "${num_transactions_processed}"
    fi

    output_data "Current synchronized block nonce" "${nonce} / ${probable_highest_nonce}"
    output_data "Current consensus round" "${synchronized_round} / ${current_round}"
    
    if [ "$compact_mode" = false ]; then
      output_data "Consensus round time" "${round_time}s"
    fi
    
    output_data "Network connected nodes" "${connected_nodes}"
    output_data "Live validator nodes" "${live_validator_nodes}"
    output_data "This node is connected to" "${num_connected_peers} peers"
    
    if [ "$compact_mode" = false ]; then
      echo ""
      echo "${bold_text}Resource usage:${normal_text}"
      output_data "CPU load" "${cpu_load_percent}%"
      echo ""
      output_data "Memory load" "${mem_load_percent}%"
      output_data "Total available memory" "${mem_total}"
      output_data "Memory consumed by golang" "${mem_used_golang}"
      output_data "Memory consumed by system" "${mem_used_sys}"
      echo ""
      output_data "Network - received" "${network_recv_percent}% - rate: ${network_recv_bps}/s - peak rate: ${network_recv_bps_peak}/s"
      output_data "Network - sent" "${network_sent_percent}% - rate: ${network_sent_bps}/s - peak rate: ${network_sent_bps_peak}/s"
    fi
    
    echo ""
  else
    error_message "The node ${host} doesn't respond with a valid response - are you sure the node is online?"
    echo ""
  fi
}

parse_variables_from_json() {
  local tag_prefix="erd_"
  
  # Node
  app_version=$(echo "${response}" | jq ".${tag_prefix}app_version" | tr -d '"')
  node_type=$(echo "${response}" | jq ".${tag_prefix}node_type" | tr -d '"')
  num_connected_peers=$(echo "${response}" | jq ".${tag_prefix}num_connected_peers")
  
  # Consensus
  consensus_state=$(echo "${response}" | jq ".${tag_prefix}consensus_state" | tr -d '"')
  count_consensus=$(echo "${response}" | jq ".${tag_prefix}count_consensus")
  count_leader=$(echo "${response}" | jq ".${tag_prefix}count_leader")
  count_accepted_blocks=$(echo "${response}" | jq ".${tag_prefix}count_accepted_blocks")
  
  # Blocks
  current_block_hash=$(echo "${response}" | jq ".${tag_prefix}current_block_hash" | tr -d '"')
  
  current_block_size=$(echo "${response}" | jq ".${tag_prefix}current_block_size")
  convert_to_readable_byte_value "${current_block_size}"
  current_block_size=$value
  
  current_round=$(echo "${response}" | jq ".${tag_prefix}current_round")
  synchronized_round=$(echo "${response}" | jq ".${tag_prefix}synchronized_round")
  current_round_timestamp=$(echo "${response}" | jq ".${tag_prefix}current_round_timestamp")
  
  # Network
  tx_pool_load=$(echo "${response}" | jq ".${tag_prefix}tx_pool_load")
  num_transactions_processed=$(echo "${response}" | jq ".${tag_prefix}num_transactions_processed")
  connected_nodes=$(echo "${response}" | jq ".${tag_prefix}connected_nodes")
  live_validator_nodes=$(echo "${response}" | jq ".${tag_prefix}live_validator_nodes")
  is_syncing=$(echo "${response}" | jq ".${tag_prefix}is_syncing")
  nonce=$(echo "${response}" | jq ".${tag_prefix}nonce")
  probable_highest_nonce=$(echo "${response}" | jq ".${tag_prefix}probable_highest_nonce")
  round_time=$(echo "${response}" | jq ".${tag_prefix}round_time")
  
  # Resource usage
  cpu_load_percent=$(echo "${response}" | jq ".${tag_prefix}cpu_load_percent")
  
  mem_load_percent=$(echo "${response}" | jq ".${tag_prefix}mem_load_percent")
  
  mem_total=$(echo "${response}" | jq ".${tag_prefix}mem_total")
  convert_to_readable_byte_value "${mem_total}"
  mem_total=$value
  
  mem_used_golang=$(echo "${response}" | jq ".${tag_prefix}mem_used_golang")
  convert_to_readable_byte_value "${mem_used_golang}"
  mem_used_golang=$value
  
  mem_used_sys=$(echo "${response}" | jq ".${tag_prefix}mem_used_sys")
  convert_to_readable_byte_value "${mem_used_sys}"
  mem_used_sys=$value
  
  network_recv_bps=$(echo "${response}" | jq ".${tag_prefix}network_recv_bps")
  convert_to_readable_byte_value "${network_recv_bps}"
  network_recv_bps=$value
  
  network_recv_bps_peak=$(echo "${response}" | jq ".${tag_prefix}network_recv_bps_peak")
  convert_to_readable_byte_value "${network_recv_bps_peak}"
  network_recv_bps_peak=$value
  
  network_recv_percent=$(echo "${response}" | jq ".${tag_prefix}network_recv_percent")
  
  network_sent_bps=$(echo "${response}" | jq ".${tag_prefix}network_sent_bps")
  convert_to_readable_byte_value "${network_sent_bps}"
  network_sent_bps=$value
  
  network_sent_bps_peak=$(echo "${response}" | jq ".${tag_prefix}network_sent_bps_peak")
  convert_to_readable_byte_value "${network_sent_bps_peak}"
  network_sent_bps_peak=$value
  
  network_sent_percent=$(echo "${response}" | jq ".${tag_prefix}network_sent_percent")  
}

#
# Helpers
#
convert_to_integer() {
  converted=$((10#$1))
}

bytes_to_human() {
  local b=${1:-0}; local d=''; local s=0; local S=(bytes {k,m,g,t,p,e,z,y}b)
  while ((b > 1024)); do
    d="$(printf ".%02d" $((b % 1024 * 100 / 1024)))"
    b=$((b / 1024))
    let s++
  done
  formatted="$b$d ${S[$s]}"
}

convert_to_readable_byte_value() {
  convert_to_integer "${1}"
  value=$converted
  bytes_to_human "${value}"
  value=$formatted
}


#
# Formatting/outputting methods
#
set_formatting() {
  header_index=1
  
  if [ "$format_output" = true ]; then
    bold_text=$(tput bold)
    italic_text=$(tput sitm)
    normal_text=$(tput sgr0)
    black_text=$(tput setaf 0)
    red_text=$(tput setaf 1)
    green_text=$(tput setaf 2)
    yellow_text=$(tput setaf 3)
  else
    bold_text=""
    italic_text=""
    normal_text=""
    black_text=""
    red_text=""
    green_text=""
    yellow_text=""
  fi
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

output_data() {
  echo "${italic_text}${1}:${normal_text} ${bold_text}${2}${normal_text}"
}

output_separator() {
  echo "------------------------------------------------------------------------"
}

output_banner() {
  output_header "Running Elrond: Battle of Nodes status checker v${version}"
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
check() {
  initialize
  
  output_banner
  
  parse_hosts
  check_hosts
}


#
# Run the script
#
check
