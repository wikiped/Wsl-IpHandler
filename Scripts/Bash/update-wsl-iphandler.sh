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

echo_verbose "Bash Updating WSL-IpHandler..."

# Prcess Incoming Arguments
echo_debug "Starting '$0' with User ID: $EUID" ${LINENO}
echo_debug "$0 Processing Incoming Arguments:" ${LINENO}
echo_debug "$*" ${LINENO}
echo_debug "Current Directory: '$(pwd)'" ${LINENO}
echo_debug "DEBUG=${DEBUG:-}" ${LINENO}
echo_debug "VERBOSE=${VERBOSE:-}" ${LINENO}

# shellcheck source=/dev/null
source "$(resolve uninstall-wsl-iphandler.sh)" "${@:1:2}" || error ${LINENO} "executing uninstall-wsl-iphandler.sh"

# shellcheck source=/dev/null
source "$(resolve install-wsl-iphandler.sh)" "${@:3}" || error ${LINENO} "executing install-wsl-iphandler.sh"

echo_verbose "Bash Updated WSL-IpHandler..."
