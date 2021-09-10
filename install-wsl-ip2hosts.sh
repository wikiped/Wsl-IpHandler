#!/usr/bin/env bash

if [[ $EUID != 0 ]]; then
    sudo "$0" "$@"
    exit $?
fi

set -o errexit
set -o ignoreeof
set -o pipefail

import() {
	filename="$1"
	local script_path
	script_path="$(dirname -- "$0")"
	local -r script_path
	declare -rx filepath="${script_path}/$filename"
	if [[ ! -f "${filepath}" ]]; then
		printf '[FATAL] Could not find %s\n' "${filepath}" 1>&2
		exit 1
	fi
	# shellcheck disable=SC1090
	if ! source "$filepath"; then
		printf '[FATAL] Could not source %s\n' "$filepath" 1>&2
		exit 1
	else
		echo_verbose "Successfully imported: $filename"
	fi
}

import "functions.sh"

trap 'error ${LINENO}' ERR

echo "Bash Installing WSL-IpHandler..."

# Prcess Incoming Arguments
echo_verbose "Processing Incoming Arguments..."
echo_debug "DEBUG=$DEBUG" $LINENO
echo_debug "VERBOSE=$VERBOSE" $LINENO
script_source="$(wslpath "$1" 2>/dev/null)"
test -f "${script_source}" || error ${LINENO} "File Not Found: $script_source"

script_target="${2%/}/${script_source##*/}"  # Only file name from source is needed - remove path
win_hosts_edit_script_path="$3"
windows_host=$4
wsl_host=$5
wsl_ip_offset=$6
test "$wsl_ip_offset" -ge 0 -a "$wsl_ip_offset" -lt 255 || error ${LINENO} "$wsl_ip_offset - is not valid ip offset!" 1

echo_debug "script_source:  $script_source" ${LINENO}
echo_debug "script_target:  $script_target" ${LINENO}
echo_debug "windows_host:   $windows_host" ${LINENO}
echo_debug "wsl_host:       $wsl_host" ${LINENO}
echo_debug "wsl_ip_offset:  $wsl_ip_offset" ${LINENO}
echo_verbose "Finised Processing Incoming Arguments."

# Install required Package
echo_verbose "Installing Required Packages..."
install_packages
echo_verbose "Installed Required Packages."

# Set Config options in /etc/wsl.conf
echo_verbose "Setting Config Options in /etc/wsl.conf..."
set_config 'windows_host' "$windows_host" || error ${LINENO} "set_config 'windows_host'"
set_config 'wsl_host' "$wsl_host" || error ${LINENO} "set_config 'wsl_host'"
set_config 'ip_offset' "$wsl_ip_offset" || error ${LINENO} "set_config 'wsl_ip_offset'"
echo_verbose "Finised Setting Config Options in /etc/wsl.conf."

# Copy Autorun Script
echo_verbose "Copying Autorun Script..."
cp --remove-destination "${script_source}" "${script_target}" || error ${LINENO} "Error copying '$script_source' to '$script_target'"
echo_verbose "Copied Autorun Script: $script_target"

# Edit Autorun Script to use actual path to powershell script which edits windows hosts file
echo_verbose "Editing Autorun Script to use actual path to powershell script..."
var_name='win_hosts_edit_script'
echo_debug "win_hosts_edit_script_path: $win_hosts_edit_script_path"
sed -i "s%^${var_name}=.*$%${var_name}=\"${win_hosts_edit_script_path//\\/\\\\}\"%" "$script_target"
echo_verbose "Finised Editing Autorun Script to use actual path to powershell script."

# Set ownership and permisions for Autorun script
echo_verbose "Setting Autorun Script permissions..."
chown root:root "${script_target}" || error ${LINENO} "Error while chown root:root $script_target" $?
chmod +x "${script_target}" || error ${LINENO} "Error while chmod +x $script_target"
echo_verbose "Autorun Script permissions have been set."

# Craate startup script file in /etc/profile.d/
echo_verbose "Creating startup script file in /etc/profile.d/..."
profile_d_script="/etc/profile.d/run-wsl-ip2hosts.sh"
echo_debug "profile_d_script=$profile_d_script" ${LINENO}
echo "sudo PATH=\"\$PATH\" ${script_target}" > "$profile_d_script" || error ${LINENO} "Error creating $profile_d_script"
chown root:root "$profile_d_script"
chmod +x "$profile_d_script"
echo_verbose "Created startup script file: $profile_d_script"

# Add sudo permissions for $script_target to /etc/sudoers.d folder in a file wsl-ip2hosts
sudoers_file="/etc/sudoers.d/wsl-ip2hosts"
echo_verbose "Adding sudo permissions for $script_target in $sudoers_file..."
printf "ALL\tALL=(root) NOPASSWD:SETENV: %s\n" "$script_target" > "$sudoers_file"
test $? = 0 || error ${LINENO} "Error creating $sudoers_file"
chown root:root "$sudoers_file"
chmod 0440 "$sudoers_file"
echo_verbose "Added sudo permissions for $script_target in $sudoers_file..."

# Ensure sudoers.d is included in /etc/sudoers
echo_verbose "Validating that sudoers.d folder is included in /etc/sudoers..."
grep -P '#includedir\s+/etc/sudoers.d' /etc/sudoers &>/dev/null || sudo bash -c "printf \"#includedir /etc/sudoers.d\n\" >> /etc/sudoers"
echo_verbose "Successfully validated that sudoers.d folder is included in /etc/sudoers"

echo "Bash Installed wsl-ip2hosts."
