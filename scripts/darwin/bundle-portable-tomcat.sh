#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

export PORTABLE_BUNDLE_PLATFORM="darwin"
exec "${SCRIPT_DIR}/../linux/bundle-portable-tomcat.sh" "$@"
