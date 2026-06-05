$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path

$TomcatVersion = if ($env:TOMCAT_VERSION) { $env:TOMCAT_VERSION } else { '9.0.118' }
$TomcatSeries = if ($env:TOMCAT_SERIES) { $env:TOMCAT_SERIES } else { '9' }
[int]$JavaVersion = if ($env:JAVA_VERSION) { $env:JAVA_VERSION } else { 8 }
$AntVersion = if ($env:ANT_VERSION) { $env:ANT_VERSION } else { '1.10.17' }
[int]$TomcatHttpPort = if ($env:TOMCAT_HTTP_PORT) { $env:TOMCAT_HTTP_PORT } else { 18080 }
[int]$TomcatShutdownPort = if ($env:TOMCAT_SHUTDOWN_PORT) { $env:TOMCAT_SHUTDOWN_PORT } else { 18005 }
[int]$TomcatAjpPort = if ($env:TOMCAT_AJP_PORT) { $env:TOMCAT_AJP_PORT } else { 18009 }
$PortableRoot = if ($env:PORTABLE_ROOT) { $env:PORTABLE_ROOT } else { Join-Path $RepoRoot '.portable-tomcat' }
$DownloadDir = Join-Path $PortableRoot 'downloads'
$JavaBaseDir = Join-Path $PortableRoot 'java'
$AntBaseDir = Join-Path $PortableRoot 'ant'
$RuntimeDir = Join-Path $PortableRoot ("apache-tomcat-" + $TomcatVersion)
$CurrentPathFile = Join-Path $PortableRoot 'current.txt'
$JavaCurrentPathFile = Join-Path $JavaBaseDir 'current.txt'
$AntCurrentPathFile = Join-Path $AntBaseDir 'current.txt'
$ArchiveName = "apache-tomcat-$TomcatVersion.zip"
$ArchiveUrl = "https://dlcdn.apache.org/tomcat/tomcat-$TomcatSeries/v$TomcatVersion/bin/$ArchiveName"
$ChecksumUrl = "$ArchiveUrl.sha512"
$ArchivePath = Join-Path $DownloadDir $ArchiveName
$ChecksumPath = Join-Path $DownloadDir ($ArchiveName + '.sha512')
$AntArchiveName = "apache-ant-$AntVersion-bin.zip"
$AntArchiveUrl = "https://dlcdn.apache.org/ant/binaries/$AntArchiveName"
$AntChecksumUrl = "$AntArchiveUrl.sha512"
$AntArchivePath = Join-Path $DownloadDir $AntArchiveName
$AntChecksumPath = Join-Path $DownloadDir ($AntArchiveName + '.sha512')

$JavaMetadataUrl = "https://api.adoptium.net/v3/assets/latest/$JavaVersion/hotspot?architecture=x64&heap_size=normal&image_type=jdk&os=windows&vendor=eclipse"
$JavaMetadataPath = Join-Path $DownloadDir ("temurin-jdk-$JavaVersion-windows-x64.json")
$JavaHomeDir = $null
$AntHomeDir = Join-Path $AntBaseDir ("apache-ant-" + $AntVersion)
$AppSourceMode = $null

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

function Expand-PortableArchive {
    param(
        [string]$ArchivePath,
        [string]$TargetDir
    )

    $ParentDir = Split-Path -Parent $TargetDir
    $TempDir = Join-Path $ParentDir '_extract'

    New-Item -ItemType Directory -Force -Path $ParentDir | Out-Null
    Remove-Item $TargetDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $TempDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force -Path $TempDir | Out-Null

    Expand-Archive -Path $ArchivePath -DestinationPath $TempDir -Force

    $ExtractedRoot = Get-ChildItem -Path $TempDir -Directory | Select-Object -First 1
    if (-not $ExtractedRoot) {
        throw "Archive extraction failed for $ArchivePath"
    }

    Move-Item $ExtractedRoot.FullName $TargetDir
    Remove-Item $TempDir -Recurse -Force
}

function Install-PortableJava {
    Write-Host "Resolving portable JDK metadata..."
    Invoke-WebRequest -Uri $JavaMetadataUrl -OutFile $JavaMetadataPath
    $Assets = Get-Content $JavaMetadataPath -Raw | ConvertFrom-Json
    if (-not $Assets -or $Assets.Count -eq 0) {
        throw "No portable JDK asset returned by Adoptium."
    }

    $Package = $Assets[0].binary.package
    $ReleaseName = $Assets[0].release_name
    $JavaArchivePath = Join-Path $DownloadDir $Package.name
    $script:JavaHomeDir = Join-Path $JavaBaseDir "$ReleaseName-windows-x64"

    if (-not (Test-Path $JavaArchivePath)) {
        Write-Host "Downloading Eclipse Temurin JDK $JavaVersion..."
        Invoke-WebRequest -Uri $Package.link -OutFile $JavaArchivePath
    }

    Write-Host "Verifying Eclipse Temurin JDK..."
    $ActualHash = (Get-FileHash -Algorithm SHA256 -Path $JavaArchivePath).Hash.ToLowerInvariant()
    $ExpectedHash = $Package.checksum.ToLowerInvariant()
    if ($ActualHash -ne $ExpectedHash) {
        throw "JDK archive checksum mismatch. Expected: $ExpectedHash Actual: $ActualHash"
    }

    Write-Host "Extracting Eclipse Temurin JDK..."
    Expand-PortableArchive -ArchivePath $JavaArchivePath -TargetDir $script:JavaHomeDir
    Set-Content -Path $JavaCurrentPathFile -Value $script:JavaHomeDir
}

function Install-PortableAnt {
    if (-not (Test-Path $AntArchivePath)) {
        Write-Host "Downloading Apache Ant $AntVersion..."
        Invoke-WebRequest -Uri $AntArchiveUrl -OutFile $AntArchivePath
    }

    Write-Host "Fetching Apache Ant checksum..."
    Invoke-WebRequest -Uri $AntChecksumUrl -OutFile $AntChecksumPath

    Write-Host "Verifying Apache Ant..."
    $ExpectedHash = (((Get-Content $AntChecksumPath -Raw) -replace "`r|`n", '').Split(' ')[0]).Trim().ToLowerInvariant()
    $ActualHash = (Get-FileHash -Algorithm SHA512 -Path $AntArchivePath).Hash.ToLowerInvariant()
    if ($ExpectedHash -ne $ActualHash) {
        throw "Ant archive checksum mismatch. Expected: $ExpectedHash Actual: $ActualHash"
    }

    Write-Host "Extracting Apache Ant..."
    Expand-PortableArchive -ArchivePath $AntArchivePath -TargetDir $AntHomeDir
    Set-Content -Path $AntCurrentPathFile -Value $AntHomeDir
}

function Detect-AppSource {
    if (Test-Path (Join-Path $RepoRoot 'build\bodgeit.war')) {
        return 'war'
    }
    if ((Test-Path (Join-Path $RepoRoot 'build\WEB-INF')) -and (Test-Path (Join-Path $RepoRoot 'build\home.jsp'))) {
        return 'exploded'
    }
    return 'build-required'
}

function Build-AppIfNeeded {
    param([string]$Mode)

    if ($Mode -ne 'build-required') {
        return $Mode
    }

    Write-Host "No prebuilt BodgeIt artifact found in build/. Falling back to portable Ant build..."
    Install-PortableAnt

    $env:JAVA_HOME = $JavaHomeDir
    $env:JRE_HOME = ''
    $env:PATH = (Join-Path $JavaHomeDir 'bin') + ';' + (Join-Path $AntHomeDir 'bin') + ';' + $env:PATH

    Push-Location $RepoRoot
    try {
        & (Join-Path $AntHomeDir 'bin\ant.bat') build
    } finally {
        Pop-Location
    }

    $UpdatedMode = Detect-AppSource
    if ($UpdatedMode -eq 'build-required') {
        throw "Portable build completed, but no deployable artifact was produced in build/."
    }

    return $UpdatedMode
}

function Install-BodgeItPayload {
    param([string]$Mode)

    Remove-Item (Join-Path $RuntimeDir 'webapps\bodgeit') -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $RuntimeDir 'webapps\bodgeit.war') -Force -ErrorAction SilentlyContinue

    switch ($Mode) {
        'war' {
            Write-Host "Installing BodgeIt WAR..."
            Copy-Item (Join-Path $RepoRoot 'build\bodgeit.war') (Join-Path $RuntimeDir 'webapps\bodgeit.war')
        }
        'exploded' {
            Write-Host "Installing exploded BodgeIt webapp..."
            Copy-Item (Join-Path $RepoRoot 'build') (Join-Path $RuntimeDir 'webapps\bodgeit') -Recurse
        }
        default {
            throw "No deployable BodgeIt artifact is available."
        }
    }
}

$TomcatHttpPort = Get-FreePort $TomcatHttpPort
$TomcatShutdownPort = Get-FreePort $TomcatShutdownPort
$TomcatAjpPort = Get-FreePort $TomcatAjpPort

New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
New-Item -ItemType Directory -Force -Path $JavaBaseDir | Out-Null
New-Item -ItemType Directory -Force -Path $AntBaseDir | Out-Null

Install-PortableJava
$AppSourceMode = Detect-AppSource
$AppSourceMode = Build-AppIfNeeded $AppSourceMode

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

Install-BodgeItPayload $AppSourceMode

$SetEnvBat = @"
@echo off
set "CATALINA_BASE=$RuntimeDir"
set "CATALINA_HOME=$RuntimeDir"
set "JAVA_HOME=$JavaHomeDir"
set "JRE_HOME="
set "JAVA_OPTS=%JAVA_OPTS% -Djava.awt.headless=true"
"@
Set-Content -Path (Join-Path $RuntimeDir 'bin\setenv.bat') -Value $SetEnvBat

Set-Content -Path $CurrentPathFile -Value $RuntimeDir

Write-Host ""
Write-Host "Portable Tomcat is ready."
Write-Host "Location: $RuntimeDir"
Write-Host "Java:     $JavaHomeDir"
if (Test-Path $AntCurrentPathFile) {
    Write-Host "Ant:      $((Get-Content $AntCurrentPathFile -First 1).Trim())"
}
Write-Host "Start:    powershell -ExecutionPolicy Bypass -File .\scripts\windows\start-portable-tomcat.ps1"
Write-Host "Stop:     powershell -ExecutionPolicy Bypass -File .\scripts\windows\stop-portable-tomcat.ps1"
Write-Host "URL:      http://127.0.0.1:$TomcatHttpPort/bodgeit"
