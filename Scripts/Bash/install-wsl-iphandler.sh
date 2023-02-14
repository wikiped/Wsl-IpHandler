#!/usr/bin/env bash
echo  "ID: $EUID Starting $0 $*"
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

echo_verbose "Bash Installing Wsl-IpHandler..."

# Prcess Incoming Arguments
echo_debug "Starting '$0' with User ID: $EUID" ${LINENO}
echo_debug "Incoming Arguments:" ${LINENO}
echo_debug "$*" ${LINENO}
echo_debug "Current Directory: '$(pwd)'" ${LINENO}
echo_debug "DEBUG=${DEBUG:-}" ${LINENO}
echo_debug "VERBOSE=${VERBOSE:-}" ${LINENO}
echo_debug "arg1=${1}" ${LINENO}
echo_debug "arg2=${2}" ${LINENO}
echo_debug "arg3=${3}" ${LINENO}
echo_debug "arg4=${4}" ${LINENO}
echo_debug "arg5=${5}" ${LINENO}
echo_debug "arg6=${6}" ${LINENO}
echo_debug "arg7=${7}" ${LINENO}

script_source=$(wslpath -u "$1" 2>/dev/null)
echo_debug "script_source:               $script_source" ${LINENO}

test -f "${script_source}" || error ${LINENO} "File Not Found: $script_source"

readonly script_target="${2%/}/${script_source##*/}"  # Use file name only: ##*/ -> removes path
readonly win_hosts_edit_script_path="$3"
readonly config="${4:-'/etc/wsl-iphandler.conf'}"
readonly windows_host=$5
readonly wsl_host=$6
readonly wsl_static_ip_or_offset=$7

echo_debug "script_target:               $script_target" ${LINENO}
echo_debug "config:                      $config" ${LINENO}
echo_debug "windows_host:                $windows_host" ${LINENO}
echo_debug "wsl_host:                    $wsl_host" ${LINENO}
echo_debug "wsl_static_ip_or_offset:     $wsl_static_ip_or_offset" ${LINENO}
echo_debug "win_hosts_edit_script_path:  $win_hosts_edit_script_path" ${LINENO}
echo_verbose "Finished Processing Incoming Arguments."

if is_valid_ip_address "$wsl_static_ip_or_offset"
then
	wsl_static_ip="$wsl_static_ip_or_offset"
	wsl_ip_offset=""
else
	wsl_static_ip=""
	wsl_ip_offset="$wsl_static_ip_or_offset"
	test "$wsl_ip_offset" -ge 0 -a "$wsl_ip_offset" -lt 255 || error ${LINENO} "$wsl_ip_offset - is not valid ip offset!" 1
fi

# Install required Package
echo_verbose "Installing Required Packages..."
install_packages
echo_verbose "Installed Required Packages."

# Set Config options
echo_verbose "Setting Config Options in $config..."
set_config 'windows_host' "$windows_host" "$config" || error ${LINENO} "set_config 'windows_host'"
set_config 'wsl_host' "$wsl_host" "$config" || error ${LINENO} "set_config 'wsl_host'"
if [[ -n "$wsl_static_ip" ]]
then
	set_config 'static_ip' "$wsl_static_ip" "$config" || error ${LINENO} "set_config 'static_ip' $wsl_static_ip"
else
	set_config 'ip_offset' "$wsl_ip_offset" "$config" || error ${LINENO} "set_config 'ip_offset' $wsl_ip_offset"
fi
echo_verbose "Finished Setting Config Options in $config"

# Copy Autorun Script
echo_verbose "Copying Autorun Script..."
cp --remove-destination "${script_source}" "${script_target}" || error ${LINENO} "Error copying '$script_source' to '$script_target'"
echo_verbose "Copied Autorun Script: $script_target"

# Edit Autorun Script to use actual path to powershell script which edits windows hosts file
echo_verbose "Editing Autorun Script to use actual path to powershell script..."
var_name='win_hosts_edit_script'
echo_debug "win_hosts_edit_script_path: $win_hosts_edit_script_path" ${LINENO}
sed -i "s%${var_name}=.*$%${var_name}=\"${win_hosts_edit_script_path//\\/\\\\}\"%" "$script_target"
echo_verbose "Finished Editing Autorun Script to use actual path to powershell script."

# Edit Autorun Script to use actual path to module's config file
echo_verbose "Editing Autorun Script to use actual path to module's config file..."
var_name='config'
echo_debug "config: $config" ${LINENO}
sed -i "s%${var_name}=.*$%${var_name}='${config}'%" "$script_target"
echo_verbose "Finished Editing Autorun Script to use actual path to module's config file."

# Set ownership and permissions for Autorun script
echo_verbose "Setting Autorun Script permissions..."
chown root:root "${script_target}" || error ${LINENO} "Error while chown root:root $script_target" $?
chmod +x "${script_target}" || error ${LINENO} "Error while chmod +x $script_target"
echo_verbose "Autorun Script permissions have been set."

# Create startup script file in /etc/profile.d/
echo_verbose "Creating startup script file in /etc/profile.d/..."
profile_d_script="/etc/profile.d/run-wsl-iphandler.sh"
echo_debug "profile_d_script=$profile_d_script" ${LINENO}
echo "sudo PATH=\"\$PATH\" ${script_target}" > "$profile_d_script" || error ${LINENO} "Error creating $profile_d_script"
chown root:root "$profile_d_script"
chmod +x "$profile_d_script"
echo_verbose "Created startup script file: $profile_d_script"

# Add sudo permissions for $script_target to /etc/sudoers.d folder in a file wsl-iphandler
sudoers_file="/etc/sudoers.d/wsl-iphandler"
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

echo_verbose "Bash Installed Wsl-IpHandler!"
