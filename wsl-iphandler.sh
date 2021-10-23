#!/usr/bin/env bash

set -o errexit
set -o ignoreeof
set -o pipefail

# if [ -n "${DEBUG:-}" ]; then
# 	set -o xtrace
# fi

# if [ -n "${VERBOSE:-}" ]; then
# 	set -o verbose
# fi

declare -r dev='eth0'
declare -r win_hosts_edit_script='Should be substituted during installation by install-wsl-iphandler.sh'

echo_log() {
	local message="$1"
	local parent_lineno="${2:+"#${2}: "}"
	local caller="${3}"
	local level="${4:-'INFO'}"
	if [[ -z "$caller" ]]; then
		case "${#FUNCNAME[@]}" in
			1)
				caller="${FUNCNAME[0]}"
				;;
			2)
				caller="${FUNCNAME[1]}"
				;;
			*)
				caller="${FUNCNAME[3]}"
				;;
		esac
	fi

	printf '[%s @ %s] %s%s\n' "$level" "$caller" "$parent_lineno" "$message"
}

echo_verbose() {
	if [[ -n "${VERBOSE:-}" ]]; then
		echo_log "$1" "$2" "${FUNCNAME[1]}" "VERBOSE"
	fi
}

echo_debug() {
	if [[ -n "${DEBUG:-}" ]]; then
		echo_log "$1" "$2" "${FUNCNAME[1]}" "DEBUG"
	fi
}

error() {
	local message="$1"
	local parent_lineno="$2"
	local code="${3:-1}"
	local -a callers
	local -i n_callers=$((${#FUNCNAME[@]} - 1))

	# shellcheck disable=SC2001
	callers="$(echo "${FUNCNAME[@]:1:$n_callers}" | sed 's/, / -> /g')"
	if [[ -n "$message" ]] ; then
		echo "[Error in $callers] ${code} on or near line ${parent_lineno}: ${message}" 1>&2
	else
		echo "[Error in $callers] ${code} on or near line ${parent_lineno}" 1>&2
	fi
	exit "${code}"
}

trap 'error ${LINENO}' ERR

set_or_echo() {
	local result
	local __result_var__
	result="$1"
	__result_var__="$2"
	if [[ "$__result_var__" ]]; then
		eval "$__result_var__='$result'"
	else
		echo "$result"
	fi
}

get_config() {
	local key
	local default
	local value
	local caller
	if [[ ${#FUNCNAME[@]} = 1 ]]; then
		caller="${FUNCNAME[0]}"
	else
		caller="${FUNCNAME[1]}"
	fi
	key="${1:?"Key cannot be empty in get_config"}"
	default="${2}"
	value=$(grep -Po --color=never "$key\s*=.*" /etc/wsl.conf 2>/dev/null | cut -d= -f2 | sed 's/^[[:space:]]*//' 2>/dev/null)

	if [[ -n "$value" ]]; then
		echo "$value"
	else
		if [[ "$#" -eq 1 ]]; then
			error ${LINENO} "${caller}: Could not find Key '$key' in /etc/wsl.conf/" 11
		else
			echo "$default"
		fi
	fi
}

get_ip_with_prefix() {
	# First Active IP address with prefix from `ip addr show`
	ip addr show dev $dev | grep -Po --color=never "inet \K[\d\./]+" 2>/dev/null | cut -d$'\n' -f1
}

ip_exists() {
	set +o pipefail
	local ip_addr=$1
	if ip addr show dev $dev | grep -Po "inet \K[\d\./]+" 2>/dev/null | grep -qF "$ip_addr"
	then
		set -o pipefail
		true
	else
		set -o pipefail
		false
	fi
}

get_new_ip_with_prefix_from_offset() {
	local start_ip
	start_ip=${1%/*}
	local suffix
	suffix=$(echo "$1" | grep -Po --color=never '/\K[\d]+$')
	suffix=${suffix:=24}
	local three_octets
	three_octets=$(echo "$start_ip" | cut -d. -f1-3)
	local last_octet
	last_octet=$(echo "$start_ip" | cut -d. -f4)
	local offset
	offset="$2"
	test "$offset" -ge 0 || error ${LINENO} "get_new_ip_with_prefix_from_offset: offset must be 0+ -> not: $offset" 1
	test "$offset" -lt 255 || error ${LINENO} "get_new_ip_with_prefix_from_offset: offset must be < 255 -> not: $offset" 2

	if [[ "$offset" -eq 0 ]]
	then
		get_ip_with_prefix
	else
		local new_octet
		new_octet=$((last_octet + offset))
		if [[ $new_octet -gt 255 ]]; then
			new_octet=$((new_octet - 255))
		fi
		echo "${three_octets}.${new_octet}/${suffix}"
	fi
}

ip_addr_add() {
	local ip_prefix
	case $# in
		1)
			ip_prefix=$1
			;;
		2)
			ip_prefix="${1}/${2}"
			;;
		*)
			error ${LINENO} "ip_addr_add needs either 1: 'id_address/suffix' or 2: 'id_address' 'suffix' paramenter(s)." 3
			;;
	esac

	local label
	label="${dev}:wsliphndlr"  # Number of symbols after ':' must not exceed 10!
	ip addr add "$ip_prefix" broadcast + dev $dev label $label
}

ip_addr_del() {
	local ip_prefix
	case $# in
		1 )
			ip_prefix=$1
			;;
		2 )
			ip_prefix="${1}/${2}"
			;;
		* )
			error ${LINENO} "ip_addr_add needs either 1: 'id_address/suffix' or 2: 'id_address' 'suffix' paramenter(s)." 4
			;;
	esac

	ip addr del "$ip_prefix" dev $dev
}

get_nameserver_ip() {
	tail -1 /etc/resolv.conf | cut -d' ' -f2 2>/dev/null || error ${LINENO} "Error parsing IP" 5
}

get_default_gateway_ip() {
	ip route show | grep --color=never '^default.*' | grep -Po '\b[\d\.]+\b' 2>/dev/null
}

get_gateway_prefix_length() {
	ip route show | grep -Po --color=never '^[\d\./]+' | cut -d/ -f2
}

add_entry_to_hosts() {
	local hostname
	hostname=$1
	local ip
	ip=$2
	if grep "$hostname" /etc/hosts &>/dev/null
	then
		# if the domain name is in /etc/hosts - replace it
		sed -i "/$hostname/ s/.*/$ip\t$hostname/" /etc/hosts
	else
		# if not - add it
		printf "%s\t%s\n" "$ip" "$hostname" >> /etc/hosts
	fi
}

add_wsl_ip_address() {
	local current_ip_addr
	current_ip_addr="$(get_ip_with_prefix)"
	echo_debug "current_ip_addr=$current_ip_addr"

	local new_ip_address
	new_ip_address="${1:?'new_ip_address is required to add_wsl_ip_address'}"
	echo_debug "new_ip_address=$new_ip_address"

	if ip_exists "$new_ip_address"
	then
		echo_verbose "IP address $new_ip_address already exists!"
	else
		ip_addr_del "$current_ip_addr" || error ${LINENO} "(ip_addr_del $current_ip_addr) failed." 14
		echo_verbose "Deleted existing IP address: $current_ip_addr"

		ip_addr_add "$new_ip_address" || error ${LINENO} "(ip_addr_add $new_ip_address) failed." 15
		echo_verbose "Added new IP address: $new_ip_address"
	fi
}

process_windows_host_and_ip() {
	echo_debug "Starting..."
	local windows_ip
	windows_ip="${1:?'windows_ip is required to process_windows_host_and_ip'}"
	windows_ip="${windows_ip%/*}"  # Remove suffix
	echo_debug "windows_ip=$windows_ip"

	local windows_host
	windows_host="${2:?'windows_host is required to process_windows_host_and_ip'}"
	echo_debug "windows_host=$windows_host"

	add_entry_to_hosts "$windows_host" "$windows_ip"

	if [[ $(get_default_gateway_ip) != "$windows_ip" ]]
	then
		ip route add "$windows_ip" dev $dev
		test $? = 0 || error ${LINENO} "(ip route add default via $windows_ip dev $dev) failed." 16
		ip route add default via "$windows_ip" dev $dev
		test $? = 0 || error ${LINENO} "(ip route add default via $windows_ip dev $dev) failed." 17
	fi
}

run_powershell_script_to_edit_windows_hosts() {
	local ps_script
	ps_script="${1:?'script path is required for run_powershell_script_to_edit_windows_hosts'}"
	local ip_address
	ip_address="${2:?'ip_address is required for run_powershell_script_to_edit_windows_hosts'}"
	ip_address="${ip_address%/*}"  # Remove suffix
	local wsl_host
	wsl_host="${3:?'wsl_host is required for run_powershell_script_to_edit_windows_hosts'}"
	test -f "$(wslpath "$ps_script")" || error ${LINENO} "PowerShell script to edit windows hosts file not found: '$ps_script'"

	# Use PowerShellCore if installed, otherwise fallback to Windows Powershell
	local psexe
	psexe="$(type -p pwsh.exe || type -p powershell.exe)"
	# psexe="/mnt/c/Program Files/PowerShell/7/pwsh.exe"
	test $? = 0 -o -z "$psexe" || error ${LINENO} 'Could not locate PowerShell executable.' 18

	#echo "${psexe}" "${ps_script}" "${ip_address%/*}" "${wsl_host}"
	"${psexe}" "${ps_script}" "${ip_address}" "${wsl_host}"
	test $? = 0 || error ${LINENO} "Error executing ${ps_script} ${ip_address} ${wsl_host}" 19

	echo_verbose "Added ${ip_address} ${wsl_host} to windows hosts file!"
}

main() {
	# Process Local IP and Host
	local ip_address
	ip_address=$(get_config 'static_ip' '')
	echo_debug "ip_address=$ip_address"

	# Get IP address for this WSL Instance
	local wsl_ip_address
	if [[ "$ip_address" ]]
	then
		wsl_ip_address="$ip_address"
		echo_debug "wsl_ip_address=$wsl_ip_address"
	else
		local gateway_ip
		gateway_ip=$(get_default_gateway_ip)
		test $? = 0 || error ${LINENO} "'get_default_gateway_ip' failed." 10
		echo_debug "gateway_ip=$gateway_ip"

		local gateway_prefix
		gateway_prefix=$(get_gateway_prefix_length)
		test $? = 0 || error ${LINENO} "'get_gateway_prefix_length' failed." 11
		echo_debug "gateway_prefix=$gateway_prefix"

		local gateway_ip_with_prefix
		gateway_ip_with_prefix="$gateway_ip/$gateway_prefix"
		test -n "$gateway_ip_with_prefix" || error ${LINENO} "No gateway IP found!" 12
		echo_debug "gateway_ip_with_prefix=$gateway_ip_with_prefix"

		local offset
		offset=$(get_config 'ip_offset')
		echo_debug "offset=$offset"
		wsl_ip_address="$(get_new_ip_with_prefix_from_offset "$gateway_ip_with_prefix" "$offset")"
		echo_debug "wsl_ip_address=$wsl_ip_address"
	fi

	# Register new WSL Instance IP address (i.e. ip addr add ...)
	echo_verbose "Adding IP: $wsl_ip_address to dev: $dev ..."
	add_wsl_ip_address "$wsl_ip_address"

	local wsl_host
	wsl_host="$(get_config 'wsl_host')"
	echo_debug "wsl_host=$wsl_host"

	# Process locally Windows Host and IP
	local windows_ip
	windows_ip="$(get_nameserver_ip)"
	test $? || error ${LINENO} "get_nameserver_ip failed" 7
	echo_debug "windows_ip=$windows_ip"

	local windows_host
	windows_host="$(get_config 'windows_host')"
	echo_debug "windows_host=$windows_host"

	process_windows_host_and_ip "$windows_ip" "$windows_host"

	# Process local Host and IP on Windows
	run_powershell_script_to_edit_windows_hosts "$win_hosts_edit_script" "$wsl_ip_address" "$wsl_host"

	echo "Host name: $wsl_host IP Address: ${wsl_ip_address%/*} added to Windows hosts!"
}

main
