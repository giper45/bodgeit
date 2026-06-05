#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

TOMCAT_VERSION="${TOMCAT_VERSION:-9.0.118}"
TOMCAT_SERIES="${TOMCAT_SERIES:-9}"
ANT_VERSION="${ANT_VERSION:-1.10.17}"
JAVA_VERSION="${JAVA_VERSION:-8}"
TOMCAT_HTTP_PORT="${TOMCAT_HTTP_PORT:-18080}"
TOMCAT_SHUTDOWN_PORT="${TOMCAT_SHUTDOWN_PORT:-18005}"
TOMCAT_AJP_PORT="${TOMCAT_AJP_PORT:-18009}"
PORTABLE_ROOT="${PORTABLE_ROOT:-${REPO_ROOT}/.portable-tomcat}"
DOWNLOAD_DIR="${PORTABLE_ROOT}/downloads"
JAVA_BASE_DIR="${PORTABLE_ROOT}/java"
ANT_BASE_DIR="${PORTABLE_ROOT}/ant"
RUNTIME_DIR="${PORTABLE_ROOT}/apache-tomcat-${TOMCAT_VERSION}"
CURRENT_LINK="${PORTABLE_ROOT}/current"
CURRENT_PATH_FILE="${PORTABLE_ROOT}/current.txt"
JAVA_CURRENT_PATH_FILE="${JAVA_BASE_DIR}/current.txt"
ANT_CURRENT_PATH_FILE="${ANT_BASE_DIR}/current.txt"
ARCHIVE_NAME="apache-tomcat-${TOMCAT_VERSION}.tar.gz"
ARCHIVE_URL="https://dlcdn.apache.org/tomcat/tomcat-${TOMCAT_SERIES}/v${TOMCAT_VERSION}/bin/${ARCHIVE_NAME}"
CHECKSUM_URL="${ARCHIVE_URL}.sha512"
ARCHIVE_PATH="${DOWNLOAD_DIR}/${ARCHIVE_NAME}"
CHECKSUM_PATH="${DOWNLOAD_DIR}/${ARCHIVE_NAME}.sha512"
ANT_ARCHIVE_NAME="apache-ant-${ANT_VERSION}-bin.tar.gz"
ANT_ARCHIVE_URL="https://dlcdn.apache.org/ant/binaries/${ANT_ARCHIVE_NAME}"
ANT_CHECKSUM_URL="${ANT_ARCHIVE_URL}.sha512"
ANT_ARCHIVE_PATH="${DOWNLOAD_DIR}/${ANT_ARCHIVE_NAME}"
ANT_CHECKSUM_PATH="${DOWNLOAD_DIR}/${ANT_ARCHIVE_NAME}.sha512"

ADOPTIUM_OS=""
ADOPTIUM_ARCH=""
JAVA_ARCHIVE_NAME=""
JAVA_ARCHIVE_PATH=""
JAVA_METADATA_PATH=""
JAVA_RELEASE_NAME=""
JAVA_PACKAGE_LINK=""
JAVA_PACKAGE_CHECKSUM=""
JAVA_HOME_DIR=""
APP_SOURCE_MODE=""

require_cmd() {
	if ! command -v "$1" >/dev/null 2>&1; then
		echo "Missing required command: $1" >&2
		exit 1
	fi
}

extract_json_value() {
	local key="$1"
	local file_path="$2"

	sed -n "s/.*\"${key}\":[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "${file_path}" | head -n 1
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
		local algorithm="$2"
		shasum -a "${algorithm}" "$1" | awk '{print $1}'
	elif command -v sha512sum >/dev/null 2>&1; then
		case "$2" in
			256) sha256sum "$1" | awk '{print $1}' ;;
			512) sha512sum "$1" | awk '{print $1}' ;;
			*) echo "Unsupported hash algorithm: $2" >&2; exit 1 ;;
		esac
	else
		echo "Neither shasum nor sha512sum is available." >&2
		exit 1
	fi
}

detect_platform() {
	local os_name
	local arch_name

	os_name="$(uname -s)"
	arch_name="$(uname -m)"

	case "${os_name}" in
		Linux) ADOPTIUM_OS="linux" ;;
		*)
			echo "This script supports Linux only. Use the Windows script on Windows." >&2
			exit 1
			;;
	esac

	case "${arch_name}" in
		x86_64|amd64) ADOPTIUM_ARCH="x64" ;;
		aarch64|arm64) ADOPTIUM_ARCH="aarch64" ;;
		*)
			echo "Unsupported Linux architecture for this script: ${arch_name}" >&2
			exit 1
			;;
	esac
}

load_java_metadata() {
	local metadata_url

	metadata_url="https://api.adoptium.net/v3/assets/latest/${JAVA_VERSION}/hotspot?architecture=${ADOPTIUM_ARCH}&heap_size=normal&image_type=jdk&os=${ADOPTIUM_OS}&vendor=eclipse"
	curl -fsSL "${metadata_url}" -o "${JAVA_METADATA_PATH}"

	JAVA_RELEASE_NAME="$(extract_json_value "release_name" "${JAVA_METADATA_PATH}")"
	JAVA_PACKAGE_LINK="$(extract_json_value "link" "${JAVA_METADATA_PATH}")"
	JAVA_PACKAGE_CHECKSUM="$(extract_json_value "checksum" "${JAVA_METADATA_PATH}")"

	if [ -z "${JAVA_RELEASE_NAME}" ] || [ -z "${JAVA_PACKAGE_LINK}" ] || [ -z "${JAVA_PACKAGE_CHECKSUM}" ]; then
		echo "Failed to parse Adoptium metadata from ${JAVA_METADATA_PATH}." >&2
		exit 1
	fi

	JAVA_ARCHIVE_NAME="$(basename "${JAVA_PACKAGE_LINK}")"
	JAVA_ARCHIVE_PATH="${DOWNLOAD_DIR}/${JAVA_ARCHIVE_NAME}"
	JAVA_HOME_DIR="${JAVA_BASE_DIR}/${JAVA_RELEASE_NAME}-${ADOPTIUM_OS}-${ADOPTIUM_ARCH}"
}

verify_sha512_file() {
	local archive_path="$1"
	local checksum_path="$2"
	local expected_hash
	local actual_hash

	expected_hash="$(tr -d '\r\n' < "${checksum_path}" | awk '{print $1}')"
	actual_hash="$(hash_file "${archive_path}" 512)"

	if [ "${expected_hash}" != "${actual_hash}" ]; then
		echo "Checksum mismatch for ${archive_path}." >&2
		echo "Expected: ${expected_hash}" >&2
		echo "Actual:   ${actual_hash}" >&2
		exit 1
	fi
}

verify_sha256_value() {
	local archive_path="$1"
	local expected_hash="$2"
	local actual_hash

	actual_hash="$(hash_file "${archive_path}" 256)"

	if [ "${expected_hash}" != "${actual_hash}" ]; then
		echo "Checksum mismatch for ${archive_path}." >&2
		echo "Expected: ${expected_hash}" >&2
		echo "Actual:   ${actual_hash}" >&2
		exit 1
	fi
}

extract_tarball_to_dir() {
	local archive_path="$1"
	local target_dir="$2"
	local parent_dir
	local root_entry
	local extracted_root

	parent_dir="$(dirname "${target_dir}")"
	mkdir -p "${parent_dir}"
	rm -rf "${target_dir}"

	root_entry="$(tar -tzf "${archive_path}" | head -1 | cut -d/ -f1)"
	tar -xzf "${archive_path}" -C "${parent_dir}"
	extracted_root="${parent_dir}/${root_entry}"

	if [ "${extracted_root}" != "${target_dir}" ]; then
		mv "${extracted_root}" "${target_dir}"
	fi
}

install_portable_java() {
	echo "Resolving portable JDK metadata..."
	load_java_metadata

	if [ ! -f "${JAVA_ARCHIVE_PATH}" ]; then
		echo "Downloading Eclipse Temurin JDK ${JAVA_VERSION}..."
		curl -fsSL "${JAVA_PACKAGE_LINK}" -o "${JAVA_ARCHIVE_PATH}"
	fi

	echo "Verifying Eclipse Temurin JDK..."
	verify_sha256_value "${JAVA_ARCHIVE_PATH}" "${JAVA_PACKAGE_CHECKSUM}"

	echo "Extracting Eclipse Temurin JDK..."
	extract_tarball_to_dir "${JAVA_ARCHIVE_PATH}" "${JAVA_HOME_DIR}"
	printf '%s\n' "${JAVA_HOME_DIR}" > "${JAVA_CURRENT_PATH_FILE}"
}

install_portable_ant() {
	if [ ! -f "${ANT_ARCHIVE_PATH}" ]; then
		echo "Downloading Apache Ant ${ANT_VERSION}..."
		curl -fsSL "${ANT_ARCHIVE_URL}" -o "${ANT_ARCHIVE_PATH}"
	fi

	echo "Fetching Apache Ant checksum..."
	curl -fsSL "${ANT_CHECKSUM_URL}" -o "${ANT_CHECKSUM_PATH}"
	echo "Verifying Apache Ant..."
	verify_sha512_file "${ANT_ARCHIVE_PATH}" "${ANT_CHECKSUM_PATH}"

	echo "Extracting Apache Ant..."
	extract_tarball_to_dir "${ANT_ARCHIVE_PATH}" "${ANT_BASE_DIR}/apache-ant-${ANT_VERSION}"
	printf '%s\n' "${ANT_BASE_DIR}/apache-ant-${ANT_VERSION}" > "${ANT_CURRENT_PATH_FILE}"
}

detect_app_source() {
	if [ -f "${REPO_ROOT}/build/bodgeit.war" ]; then
		APP_SOURCE_MODE="war"
	elif [ -d "${REPO_ROOT}/build/WEB-INF" ] && [ -f "${REPO_ROOT}/build/home.jsp" ]; then
		APP_SOURCE_MODE="exploded"
	else
		APP_SOURCE_MODE="build-required"
	fi
}

build_app_if_needed() {
	if [ "${APP_SOURCE_MODE}" != "build-required" ]; then
		return
	fi

	echo "No prebuilt BodgeIt artifact found in build/. Falling back to portable Ant build..."
	install_portable_ant

	export JAVA_HOME="${JAVA_HOME_DIR}"
	export PATH="${JAVA_HOME}/bin:${ANT_BASE_DIR}/apache-ant-${ANT_VERSION}/bin:${PATH}"

	(
		cd "${REPO_ROOT}"
		"${ANT_BASE_DIR}/apache-ant-${ANT_VERSION}/bin/ant" build
	)

	detect_app_source
	if [ "${APP_SOURCE_MODE}" = "build-required" ]; then
		echo "Portable build completed, but no deployable artifact was produced in build/." >&2
		exit 1
	fi
}

install_bodgeit_payload() {
	rm -rf "${RUNTIME_DIR}/webapps/bodgeit" "${RUNTIME_DIR}/webapps/bodgeit.war"

	case "${APP_SOURCE_MODE}" in
		war)
			echo "Installing BodgeIt WAR..."
			cp "${REPO_ROOT}/build/bodgeit.war" "${RUNTIME_DIR}/webapps/bodgeit.war"
			;;
		exploded)
			echo "Installing exploded BodgeIt webapp..."
			cp -R "${REPO_ROOT}/build" "${RUNTIME_DIR}/webapps/bodgeit"
			;;
		*)
			echo "No deployable BodgeIt artifact is available." >&2
			exit 1
			;;
	esac
}

configure_ports() {
	local server_xml="$1"
	local tmp_file

	tmp_file="${server_xml}.tmp"
	sed \
		-e "s/<Server port=\"[0-9][0-9]*\" shutdown=\"SHUTDOWN\">/<Server port=\"${TOMCAT_SHUTDOWN_PORT}\" shutdown=\"SHUTDOWN\">/" \
		-e "s/Connector port=\"[0-9][0-9]*\" protocol=\"HTTP\\/1\\.1\"/Connector port=\"${TOMCAT_HTTP_PORT}\" protocol=\"HTTP\\/1.1\"/" \
		-e "s/Connector port=\"[0-9][0-9]*\" protocol=\"AJP\\/1\\.3\" redirectPort=\"8443\"/Connector port=\"${TOMCAT_AJP_PORT}\" protocol=\"AJP\\/1.3\" redirectPort=\"8443\"/" \
		"${server_xml}" > "${tmp_file}"
	mv "${tmp_file}" "${server_xml}"
}

require_cmd curl
require_cmd tar
require_cmd lsof
require_cmd sed

detect_platform

TOMCAT_HTTP_PORT="$(pick_port "${TOMCAT_HTTP_PORT}")"
TOMCAT_SHUTDOWN_PORT="$(pick_port "${TOMCAT_SHUTDOWN_PORT}")"
TOMCAT_AJP_PORT="$(pick_port "${TOMCAT_AJP_PORT}")"

mkdir -p "${DOWNLOAD_DIR}"
mkdir -p "${JAVA_BASE_DIR}"
mkdir -p "${ANT_BASE_DIR}"

JAVA_METADATA_PATH="${DOWNLOAD_DIR}/temurin-jdk-${JAVA_VERSION}-${ADOPTIUM_OS}-${ADOPTIUM_ARCH}.json"

install_portable_java
detect_app_source
build_app_if_needed

if [ ! -f "${ARCHIVE_PATH}" ]; then
	echo "Downloading Apache Tomcat ${TOMCAT_VERSION}..."
	curl -fsSL "${ARCHIVE_URL}" -o "${ARCHIVE_PATH}"
fi

echo "Fetching checksum..."
curl -fsSL "${CHECKSUM_URL}" -o "${CHECKSUM_PATH}"
verify_sha512_file "${ARCHIVE_PATH}" "${CHECKSUM_PATH}"

if [ ! -d "${RUNTIME_DIR}" ]; then
	echo "Extracting Apache Tomcat ${TOMCAT_VERSION}..."
	tar -xzf "${ARCHIVE_PATH}" -C "${PORTABLE_ROOT}"
fi

echo "Configuring Tomcat ports..."
configure_ports "${RUNTIME_DIR}/conf/server.xml"

install_bodgeit_payload

cat > "${RUNTIME_DIR}/bin/setenv.sh" <<EOF
#!/usr/bin/env bash
export CATALINA_BASE="${RUNTIME_DIR}"
export CATALINA_HOME="${RUNTIME_DIR}"
export JAVA_HOME="${JAVA_HOME_DIR}"
export JRE_HOME=""
export JAVA_OPTS="\${JAVA_OPTS:-} -Djava.awt.headless=true"
EOF
chmod +x "${RUNTIME_DIR}/bin/setenv.sh"

printf '%s\n' "${RUNTIME_DIR}" > "${CURRENT_PATH_FILE}"
ln -sfn "${RUNTIME_DIR}" "${CURRENT_LINK}"

echo
echo "Portable Tomcat is ready."
echo "Location: ${RUNTIME_DIR}"
echo "Java:     ${JAVA_HOME_DIR}"
if [ -f "${ANT_CURRENT_PATH_FILE}" ]; then
	echo "Ant:      $(tr -d '\r\n' < "${ANT_CURRENT_PATH_FILE}")"
fi
echo "Start:    ${REPO_ROOT}/scripts/linux/start-portable-tomcat.sh"
echo "Stop:     ${REPO_ROOT}/scripts/linux/stop-portable-tomcat.sh"
echo "URL:      http://127.0.0.1:${TOMCAT_HTTP_PORT}/bodgeit"
