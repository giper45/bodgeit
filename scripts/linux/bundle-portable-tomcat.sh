#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PORTABLE_ROOT="${PORTABLE_ROOT:-${REPO_ROOT}/.portable-tomcat}"
DIST_DIR="${DIST_DIR:-${REPO_ROOT}/dist}"
PLATFORM_NAME="${PORTABLE_BUNDLE_PLATFORM:-linux}"
CURRENT_PATH_FILE="${PORTABLE_ROOT}/current.txt"
JAVA_CURRENT_PATH_FILE="${PORTABLE_ROOT}/java/current.txt"

read_value() {
	tr -d '\r\n' < "$1"
}

require_file() {
	if [ ! -f "$1" ]; then
		echo "Missing required file: $1" >&2
		exit 1
	fi
}

require_dir() {
	if [ ! -d "$1" ]; then
		echo "Missing required directory: $1" >&2
		exit 1
	fi
}

require_file "${CURRENT_PATH_FILE}"
require_file "${JAVA_CURRENT_PATH_FILE}"

RUNTIME_NAME="$(basename "$(read_value "${CURRENT_PATH_FILE}")")"
JAVA_NAME="$(basename "$(read_value "${JAVA_CURRENT_PATH_FILE}")")"
RUNTIME_SOURCE_DIR="${PORTABLE_ROOT}/${RUNTIME_NAME}"
JAVA_SOURCE_DIR="${PORTABLE_ROOT}/java/${JAVA_NAME}"
BUNDLE_ROOT_NAME="bodgeit-portable-${PLATFORM_NAME}"
BUNDLE_WORK_DIR="${DIST_DIR}/${BUNDLE_ROOT_NAME}"
BUNDLE_PORTABLE_DIR="${BUNDLE_WORK_DIR}/portable-tomcat"
BUNDLE_RUNTIME_DIR="${BUNDLE_PORTABLE_DIR}/${RUNTIME_NAME}"
BUNDLE_JAVA_DIR="${BUNDLE_PORTABLE_DIR}/java/${JAVA_NAME}"
ARCHIVE_PATH="${DIST_DIR}/${BUNDLE_ROOT_NAME}.tar.gz"

require_dir "${RUNTIME_SOURCE_DIR}"
require_dir "${JAVA_SOURCE_DIR}"

rm -rf "${BUNDLE_WORK_DIR}"
mkdir -p "${BUNDLE_PORTABLE_DIR}/java"

cp -R "${RUNTIME_SOURCE_DIR}" "${BUNDLE_RUNTIME_DIR}"
cp -R "${JAVA_SOURCE_DIR}" "${BUNDLE_JAVA_DIR}"
printf '%s\n' "${RUNTIME_NAME}" > "${BUNDLE_PORTABLE_DIR}/current.txt"
printf '%s\n' "${JAVA_NAME}" > "${BUNDLE_PORTABLE_DIR}/java/current.txt"

cat > "${BUNDLE_RUNTIME_DIR}/bin/setenv.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR="\$(cd "\${SCRIPT_DIR}/.." && pwd)"
JAVA_DIR_NAME="\$(tr -d '\r\n' < "\${RUNTIME_DIR}/../java/current.txt")"
JAVA_HOME="\$(cd "\${RUNTIME_DIR}/../java/\${JAVA_DIR_NAME}" && pwd)"
export CATALINA_BASE="\${RUNTIME_DIR}"
export CATALINA_HOME="\${RUNTIME_DIR}"
export JAVA_HOME="\${JAVA_HOME}"
export JRE_HOME=""
export JAVA_OPTS="\${JAVA_OPTS:-} -Djava.awt.headless=true"
EOF
chmod +x "${BUNDLE_RUNTIME_DIR}/bin/setenv.sh"

cat > "${BUNDLE_WORK_DIR}/start.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR_NAME="\$(tr -d '\r\n' < "\${SCRIPT_DIR}/portable-tomcat/current.txt")"
exec "\${SCRIPT_DIR}/portable-tomcat/\${RUNTIME_DIR_NAME}/bin/startup.sh"
EOF

cat > "${BUNDLE_WORK_DIR}/stop.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
RUNTIME_DIR_NAME="\$(tr -d '\r\n' < "\${SCRIPT_DIR}/portable-tomcat/current.txt")"
exec "\${SCRIPT_DIR}/portable-tomcat/\${RUNTIME_DIR_NAME}/bin/shutdown.sh"
EOF

chmod +x "${BUNDLE_WORK_DIR}/start.sh" "${BUNDLE_WORK_DIR}/stop.sh"

mkdir -p "${DIST_DIR}"
tar -czf "${ARCHIVE_PATH}" -C "${DIST_DIR}" "${BUNDLE_ROOT_NAME}"

echo "Bundle created at ${ARCHIVE_PATH}"
