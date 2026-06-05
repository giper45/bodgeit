#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TOMCAT_VERSION="${TOMCAT_VERSION:-9.0.118}"
TOMCAT_SERIES="${TOMCAT_SERIES:-9}"
TOMCAT_HTTP_PORT="${TOMCAT_HTTP_PORT:-18080}"
TOMCAT_SHUTDOWN_PORT="${TOMCAT_SHUTDOWN_PORT:-18005}"
TOMCAT_AJP_PORT="${TOMCAT_AJP_PORT:-18009}"
PORTABLE_ROOT="${PORTABLE_ROOT:-${REPO_ROOT}/.portable-tomcat}"
DOWNLOAD_DIR="${PORTABLE_ROOT}/downloads"
RUNTIME_DIR="${PORTABLE_ROOT}/apache-tomcat-${TOMCAT_VERSION}"
CURRENT_LINK="${PORTABLE_ROOT}/current"
CURRENT_PATH_FILE="${PORTABLE_ROOT}/current.txt"
ARCHIVE_NAME="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
ARCHIVE_URL="https://dlcdn.apache.org/tomcat/tomcat-${TOMCAT_SERIES}/v${TOMCAT_VERSION}/bin/${ARCHIVE_NAME}"
CHECKSUM_URL="${ARCHIVE_URL}.sha512"
ARCHIVE_PATH="${DOWNLOAD_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${DOWNLOAD_DIR}/${ARCHIVE_NAME}.sha512"

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Missing required command: $1" >&2
		exit 1
	fi
}

port_in_use() {
	lsof -nP -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
}

RESERVED_PORTS=""

pick_port() {
	local candidate="$1"
	while port_in_use "${candidate}" || [[ " ${RESERVED_PORTS} " == *" ${candidate} "* ]]; do
		candidate=$((candidate + 1))
	done
	RESERVED_PORTS="${RESERVED_PORTS} ${candidate}"
	echo "${candidate}"
}

hash_file() {
	if command -v shasum >/dev/null 2>&1; then
		shasum -a 512 "$1" | awk '{print $1}'
	elif command -v sha512sum >/dev/null 2>&1; then
		sha512sum "$1" | awk '{print $1}'
	else
		echo "Neither shasum nor sha512sum is available." >&2
		exit 1
	fi
}

configure_ports() {
	local server_xml="$1"

	perl -0pi -e "s/<Server port=\"\\d+\" shutdown=\"SHUTDOWN\">/<Server port=\"${TOMCAT_SHUTDOWN_PORT}\" shutdown=\"SHUTDOWN\">/" "${server_xml}"
	perl -0pi -e "s/Connector port=\"\\d+\" protocol=\"HTTP\\/1\\.1\"/Connector port=\"${TOMCAT_HTTP_PORT}\" protocol=\"HTTP\\/1.1\"/" "${server_xml}"
	perl -0pi -e "s/Connector port=\"\\d+\" protocol=\"AJP\\/1\\.3\" redirectPort=\"8443\"/Connector port=\"${TOMCAT_AJP_PORT}\" protocol=\"AJP\\/1.3\" redirectPort=\"8443\"/" "${server_xml}"
}

require_cmd java
require_cmd ant
require_cmd curl
require_cmd tar
require_cmd perl
require_cmd lsof

TOMCAT_HTTP_PORT="$(pick_port "${TOMCAT_HTTP_PORT}")"
TOMCAT_SHUTDOWN_PORT="$(pick_port "${TOMCAT_SHUTDOWN_PORT}")"
TOMCAT_AJP_PORT="$(pick_port "${TOMCAT_AJP_PORT}")"

mkdir -p "${DOWNLOAD_DIR}"

echo "Building BodgeIt WAR..."
(
	cd "${REPO_ROOT}"
	ant build
)

if [ ! -f "${ARCHIVE_PATH}" ]; then
	echo "Downloading Apache Tomcat ${TOMCAT_VERSION}..."
	curl -fsSL "${ARCHIVE_URL}" -o "${ARCHIVE_PATH}"
fi

echo "Fetching checksum..."
curl -fsSL "${CHECKSUM_URL}" -o "${CHECKSUM_PATH}"

EXPECTED_HASH="$(tr -d '\r\n' < "${CHECKSUM_PATH}" | awk '{print $1}')"
ACTUAL_HASH="$(hash_file "${ARCHIVE_PATH}")"

if [ "${EXPECTED_HASH}" != "${ACTUAL_HASH}" ]; then
	echo "Tomcat archive checksum mismatch." >&2
	echo "Expected: ${EXPECTED_HASH}" >&2
	echo "Actual:   ${ACTUAL_HASH}" >&2
	exit 1
fi

if [ ! -d "${RUNTIME_DIR}" ]; then
	echo "Extracting Apache Tomcat ${TOMCAT_VERSION}..."
	tar -xzf "${ARCHIVE_PATH}" -C "${PORTABLE_ROOT}"
fi

echo "Configuring Tomcat ports..."
configure_ports "${RUNTIME_DIR}/conf/server.xml"

echo "Installing BodgeIt WAR..."
rm -rf "${RUNTIME_DIR}/webapps/bodgeit" "${RUNTIME_DIR}/webapps/bodgeit.war"
cp "${REPO_ROOT}/build/bodgeit.war" "${RUNTIME_DIR}/webapps/bodgeit.war"

cat > "${RUNTIME_DIR}/bin/setenv.sh" <<EOF
#!/usr/bin/env bash
export CATALINA_BASE="${RUNTIME_DIR}"
export CATALINA_HOME="${RUNTIME_DIR}"
export JAVA_OPTS="\${JAVA_OPTS:-} -Djava.awt.headless=true"
EOF
chmod +x "${RUNTIME_DIR}/bin/setenv.sh"

printf '%s\n' "${RUNTIME_DIR}" > "${CURRENT_PATH_FILE}"
ln -sfn "${RUNTIME_DIR}" "${CURRENT_LINK}"

echo
echo "Portable Tomcat is ready."
echo "Location: ${RUNTIME_DIR}"
echo "Start:    ${REPO_ROOT}/scripts/linux/start-portable-tomcat.sh"
echo "Stop:     ${REPO_ROOT}/scripts/linux/stop-portable-tomcat.sh"
echo "URL:      http://127.0.0.1:${TOMCAT_HTTP_PORT}/bodgeit"
