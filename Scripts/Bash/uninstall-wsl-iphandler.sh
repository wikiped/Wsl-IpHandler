#!/usr/bin/env bash

if [[ $EUID != 0 ]]; then
	sudo -E env DEBUG="${DEBUG:-}" VERBOSE="${VERBOSE:-}" "$0" "$@"
    exit $?
fi

resolve() {
	local -r filename="$1"
	local -r script_path="$(dirname -- "$0")"
	local -r filepath="${script_path}/$filename"
	if [[ -f "${filepath}" ]]; then
		printf '%s' "${filepath}"
	else
		printf '[FATAL] Could not find %s\n' "${filepath}" 1>&2
		exit 1
	fi
}

#shellcheck source=/dev/null
source "$(resolve functions.sh)"

echo_verbose "Bash Uninstalling Wsl-IpHandler..."

# Prcess Incoming Arguments
echo_debug "Starting '$0' with User ID: $EUID"
echo_debug "$0 Processing Incoming Arguments:" ${LINENO}
echo_debug "$*" ${LINENO}
echo_debug "Current Directory: '$(pwd)'" ${LINENO}
echo_debug "DEBUG=${DEBUG:-}" ${LINENO}
echo_debug "VERBOSE=${VERBOSE:-}" ${LINENO}
script_name="$1"
script_target="${2:-'/usr/local/bin'}"
script_target="${script_target%/}/${script_name##*/}"

# Remove Config options in /etc/wsl.conf
echo_verbose "Removing Config Options in /etc/wsl.conf..."
remove_config 'windows_host' || error ${LINENO} "remove_config 'windows_host'"
remove_config 'wsl_host' || error ${LINENO} "remove_config 'wsl_host'"
remove_config 'static_ip' || error ${LINENO} "remove_config 'static_ip'"
remove_config 'ip_offset' || error ${LINENO} "set_config 'ip_offset'"
echo_verbose "Finished Removing Config Options in /etc/wsl.conf."

# Remove Autorun Script
echo_verbose "Removing Autorun Script: $script_target"
if [[ -f "${script_target}" ]]
then
	rm -f "${script_target}" || error ${LINENO} "Error removing $script_target" 0
	echo_verbose "File removed: $script_target"
else
	echo_verbose "File was not found: $script_target"
fi

# Remove startup script file in /etc/profile.d/
profile_d_script="/etc/profile.d/run-wsl-iphandler.sh"
echo_verbose "Removing startup script file: $profile_d_script"
if [[ -f "${profile_d_script}" ]]
then
	rm -f "$profile_d_script" || error ${LINENO} "Error removing $profile_d_script" 0
	echo_verbose "File removed: $profile_d_script"
else
	echo_verbose "File was not found: $profile_d_script"
fi

# Remove sudoers file wsl-iphandler from /etc/sudoers.d folder
sudoers_file="/etc/sudoers.d/wsl-iphandler"
echo_verbose "Removing sudoers permissions file: $sudoers_file"
if [[ -f "${sudoers_file}" ]]
then
	rm -f "$sudoers_file" || error ${LINENO} "Error removing $sudoers_file" 0
	echo_verbose "File removed: $sudoers_file"
else
	echo_verbose "File was not found: $sudoers_file"
fi

echo_verbose "Bash Uninstalled Wsl-IpHandler."
