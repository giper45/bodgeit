#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PORTABLE_ROOT="${PORTABLE_ROOT:-${REPO_ROOT}/.portable-tomcat}"
CURRENT_PATH_FILE="${PORTABLE_ROOT}/current.txt"
CURRENT_LINK="${PORTABLE_ROOT}/current"

read_runtime_dir() {
	if [ -f "${CURRENT_PATH_FILE}" ]; then
		tr -d '\r\n' < "${CURRENT_PATH_FILE}"
	elif [ -L "${CURRENT_LINK}" ] || [ -d "${CURRENT_LINK}" ]; then
		printf '%s\n' "${CURRENT_LINK}"
	else
		echo "Portable Tomcat is not set up yet. Run ./scripts/linux/setup-portable-tomcat.sh first." >&2
		exit 1
	fi
}

RUNTIME_DIR="$(read_runtime_dir)"

if [ ! -x "${RUNTIME_DIR}/bin/shutdown.sh" ]; then
	echo "Portable Tomcat is not set up yet. Run ./scripts/linux/setup-portable-tomcat.sh first." >&2
	exit 1
fi

export CATALINA_BASE="${RUNTIME_DIR}"
export CATALINA_HOME="${RUNTIME_DIR}"

"${RUNTIME_DIR}/bin/shutdown.sh"
