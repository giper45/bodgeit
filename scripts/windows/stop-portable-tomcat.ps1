$ErrorActionPreference = 'Stop'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path
$PortableRoot = if ($env:PORTABLE_ROOT) { $env:PORTABLE_ROOT } else { Join-Path $RepoRoot '.portable-tomcat' }
$CurrentPathFile = Join-Path $PortableRoot 'current.txt'

if (-not (Test-Path $CurrentPathFile)) {
    throw "Portable Tomcat is not set up yet. Run .\scripts\windows\setup-portable-tomcat.ps1 first."
}

$RuntimeDir = (Get-Content $CurrentPathFile -First 1).Trim()
$ShutdownBat = Join-Path $RuntimeDir 'bin\shutdown.bat'

if (-not (Test-Path $ShutdownBat)) {
    throw "Portable Tomcat is not set up yet. Run .\scripts\windows\setup-portable-tomcat.ps1 first."
}

$env:CATALINA_BASE = $RuntimeDir
$env:CATALINA_HOME = $RuntimeDir

& $ShutdownBat
