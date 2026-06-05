$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$PortableRoot = if ($env:PORTABLE_ROOT) { $env:PORTABLE_ROOT } else { Join-Path $RepoRoot '.portable-tomcat' }
$DistDir = if ($env:DIST_DIR) { $env:DIST_DIR } else { Join-Path $RepoRoot 'dist' }
$CurrentPathFile = Join-Path $PortableRoot 'current.txt'
$JavaCurrentPathFile = Join-Path $PortableRoot 'java\current.txt'
$BundleRootName = 'bodgeit-portable-windows'
$BundleWorkDir = Join-Path $DistDir $BundleRootName
$BundlePortableDir = Join-Path $BundleWorkDir 'portable-tomcat'
$ArchivePath = Join-Path $DistDir ($BundleRootName + '.zip')

if (-not (Test-Path $CurrentPathFile)) {
    throw "Portable Tomcat is not set up. Run the Windows setup script first."
}

if (-not (Test-Path $JavaCurrentPathFile)) {
    throw "Portable Java is not set up. Run the Windows setup script first."
}

$RuntimeName = Split-Path ((Get-Content $CurrentPathFile -First 1).Trim()) -Leaf
$JavaName = Split-Path ((Get-Content $JavaCurrentPathFile -First 1).Trim()) -Leaf
$RuntimeSourceDir = Join-Path $PortableRoot $RuntimeName
$JavaSourceDir = Join-Path $PortableRoot ("java\" + $JavaName)
$BundleRuntimeDir = Join-Path $BundlePortableDir $RuntimeName
$BundleJavaDir = Join-Path $BundlePortableDir ("java\" + $JavaName)

if (-not (Test-Path $RuntimeSourceDir)) {
    throw "Portable Tomcat runtime directory is missing: $RuntimeSourceDir"
}

if (-not (Test-Path $JavaSourceDir)) {
    throw "Portable Java directory is missing: $JavaSourceDir"
}

Remove-Item $BundleWorkDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path (Join-Path $BundlePortableDir 'java') | Out-Null

Copy-Item $RuntimeSourceDir $BundleRuntimeDir -Recurse
Copy-Item $JavaSourceDir $BundleJavaDir -Recurse
Set-Content -Path (Join-Path $BundlePortableDir 'current.txt') -Value $RuntimeName
Set-Content -Path (Join-Path $BundlePortableDir 'java\current.txt') -Value $JavaName

$SetEnvBat = @"
@echo off
set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%..") do set "RUNTIME_DIR=%%~fI"
set /p JAVA_DIR_NAME=<"%RUNTIME_DIR%\..\java\current.txt"
for %%I in ("%RUNTIME_DIR%\..\java\%JAVA_DIR_NAME%") do set "JAVA_HOME=%%~fI"
set "CATALINA_BASE=%RUNTIME_DIR%"
set "CATALINA_HOME=%RUNTIME_DIR%"
set "JRE_HOME="
set "JAVA_OPTS=%JAVA_OPTS% -Djava.awt.headless=true"
"@
Set-Content -Path (Join-Path $BundleRuntimeDir 'bin\setenv.bat') -Value $SetEnvBat

$StartBat = @"
@echo off
setlocal
set "ROOT=%~dp0"
set /p RUNTIME_DIR_NAME=<"%ROOT%portable-tomcat\current.txt"
call "%ROOT%portable-tomcat\%RUNTIME_DIR_NAME%\bin\startup.bat"
"@
Set-Content -Path (Join-Path $BundleWorkDir 'start.bat') -Value $StartBat

$StopBat = @"
@echo off
setlocal
set "ROOT=%~dp0"
set /p RUNTIME_DIR_NAME=<"%ROOT%portable-tomcat\current.txt"
call "%ROOT%portable-tomcat\%RUNTIME_DIR_NAME%\bin\shutdown.bat"
"@
Set-Content -Path (Join-Path $BundleWorkDir 'stop.bat') -Value $StopBat

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
Remove-Item $ArchivePath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path $BundleWorkDir -DestinationPath $ArchivePath

Write-Host "Bundle created at $ArchivePath"
