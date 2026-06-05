$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path

$TomcatVersion = if ($env:TOMCAT_VERSION) { $env:TOMCAT_VERSION } else { '9.0.118' }
$TomcatSeries = if ($env:TOMCAT_SERIES) { $env:TOMCAT_SERIES } else { '9' }
[int]$TomcatHttpPort = if ($env:TOMCAT_HTTP_PORT) { $env:TOMCAT_HTTP_PORT } else { 18080 }
[int]$TomcatShutdownPort = if ($env:TOMCAT_SHUTDOWN_PORT) { $env:TOMCAT_SHUTDOWN_PORT } else { 18005 }
[int]$TomcatAjpPort = if ($env:TOMCAT_AJP_PORT) { $env:TOMCAT_AJP_PORT } else { 18009 }
$PortableRoot = if ($env:PORTABLE_ROOT) { $env:PORTABLE_ROOT } else { Join-Path $RepoRoot '.portable-tomcat' }
$DownloadDir = Join-Path $PortableRoot 'downloads'
$RuntimeDir = Join-Path $PortableRoot ("apache-tomcat-" + $TomcatVersion)
$CurrentPathFile = Join-Path $PortableRoot 'current.txt'
$ArchiveName = "apache-tomcat-$TomcatVersion.zip"
$ArchiveUrl = "https://dlcdn.apache.org/tomcat/tomcat-$TomcatSeries/v$TomcatVersion/bin/$ArchiveName"
$ChecksumUrl = "$ArchiveUrl.sha512"
$ArchivePath = Join-Path $DownloadDir $ArchiveName
$ChecksumPath = Join-Path $DownloadDir ($ArchiveName + '.sha512')

function Require-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Missing required command: $Name"
    }
}

function Get-FreePort {
    param([int]$Candidate)

    if (-not $script:ReservedPorts) {
        $script:ReservedPorts = @{}
    }

    $ports = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners() |
        Select-Object -ExpandProperty Port -Unique
    $portSet = @{}
    foreach ($port in $ports) {
        $portSet[[int]$port] = $true
    }

    while ($portSet.ContainsKey($Candidate) -or $script:ReservedPorts.ContainsKey($Candidate)) {
        $Candidate++
    }

    $script:ReservedPorts[$Candidate] = $true
    return $Candidate
}

Require-Command java
Require-Command ant
Require-Command powershell

$TomcatHttpPort = Get-FreePort $TomcatHttpPort
$TomcatShutdownPort = Get-FreePort $TomcatShutdownPort
$TomcatAjpPort = Get-FreePort $TomcatAjpPort

New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

Write-Host "Building BodgeIt WAR..."
Push-Location $RepoRoot
try {
    & ant build
} finally {
    Pop-Location
}

if (-not (Test-Path $ArchivePath)) {
    Write-Host "Downloading Apache Tomcat $TomcatVersion..."
    Invoke-WebRequest -Uri $ArchiveUrl -OutFile $ArchivePath
}

Write-Host "Fetching checksum..."
Invoke-WebRequest -Uri $ChecksumUrl -OutFile $ChecksumPath

$ExpectedHash = (((Get-Content $ChecksumPath -Raw) -replace "`r|`n", '').Split(' ')[0]).Trim().ToLowerInvariant()
$ActualHash = (Get-FileHash -Algorithm SHA512 -Path $ArchivePath).Hash.ToLowerInvariant()

if ($ExpectedHash -ne $ActualHash) {
    throw "Tomcat archive checksum mismatch. Expected: $ExpectedHash Actual: $ActualHash"
}

if (-not (Test-Path $RuntimeDir)) {
    Write-Host "Extracting Apache Tomcat $TomcatVersion..."
    Expand-Archive -Path $ArchivePath -DestinationPath $PortableRoot -Force
}

Write-Host "Configuring Tomcat ports..."
$ServerXmlPath = Join-Path $RuntimeDir 'conf\server.xml'
$ServerXml = Get-Content $ServerXmlPath -Raw
$ServerXml = $ServerXml -replace '<Server port="\d+" shutdown="SHUTDOWN">', "<Server port=`"$TomcatShutdownPort`" shutdown=`"SHUTDOWN`">"
$ServerXml = $ServerXml -replace 'Connector port="\d+" protocol="HTTP/1\.1"', "Connector port=`"$TomcatHttpPort`" protocol=`"HTTP/1.1`""
$ServerXml = $ServerXml -replace 'Connector port="\d+" protocol="AJP/1\.3" redirectPort="8443"', "Connector port=`"$TomcatAjpPort`" protocol=`"AJP/1.3`" redirectPort=`"8443`""
Set-Content -Path $ServerXmlPath -Value $ServerXml -NoNewline

Write-Host "Installing BodgeIt WAR..."
Remove-Item (Join-Path $RuntimeDir 'webapps\bodgeit') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $RuntimeDir 'webapps\bodgeit.war') -Force -ErrorAction SilentlyContinue
Copy-Item (Join-Path $RepoRoot 'build\bodgeit.war') (Join-Path $RuntimeDir 'webapps\bodgeit.war')

$SetEnvBat = @"
@echo off
set "CATALINA_BASE=$RuntimeDir"
set "CATALINA_HOME=$RuntimeDir"
set "JAVA_OPTS=%JAVA_OPTS% -Djava.awt.headless=true"
"@
Set-Content -Path (Join-Path $RuntimeDir 'bin\setenv.bat') -Value $SetEnvBat

Set-Content -Path $CurrentPathFile -Value $RuntimeDir

Write-Host ""
Write-Host "Portable Tomcat is ready."
Write-Host "Location: $RuntimeDir"
Write-Host "Start:    powershell -ExecutionPolicy Bypass -File .\scripts\windows\start-portable-tomcat.ps1"
Write-Host "Stop:     powershell -ExecutionPolicy Bypass -File .\scripts\windows\stop-portable-tomcat.ps1"
Write-Host "URL:      http://127.0.0.1:$TomcatHttpPort/bodgeit"
