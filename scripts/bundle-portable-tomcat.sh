#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNAME_S="$(uname -s)"

case "${UNAME_S}" in
	Linux) exec "${SCRIPT_DIR}/linux/bundle-portable-tomcat.sh" "$@" ;;
	Darwin) exec "${SCRIPT_DIR}/darwin/bundle-portable-tomcat.sh" "$@" ;;
	*)
		echo "Unsupported platform for this wrapper: ${UNAME_S}" >&2
		exit 1
		;;
esac
