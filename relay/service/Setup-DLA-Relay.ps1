# ============================================================================
# Setup-DLA-Relay.ps1   -   Document Loading Agent invoice relay setup
#
# Author : Claude for Gary D. Hall, 11/24/2026. Same pattern as the Stick-IT
#          relay setup (Setup-StickIT-Relay.ps1): WinSW wrapper, one service
#          per environment, settings readable by SYSTEM and Administrators only.
#
# WHAT IT DOES, IN ORDER
#   1. Asks Windows for administrator rights (a service needs them).
#   2. Asks three things:
#        - DEV or PRD: which database this relay serves. It goes in the
#          service name, so anyone looking in Services can tell.
#        - The database address (the ORDS address ending in /prd_workspace).
#        - The relay token (DLA_SETTINGS, setting RELAY_TOKEN, in that
#          database). It is checked, then written only to the settings file.
#   3. Checks the address and token with the database: sends an empty
#      request to the relay's documents endpoint. The database answers
#      "400, a field is missing" when the token is right and "401" when it is
#      wrong. Nothing is stored either way. Nothing is installed unless the
#      token is accepted.
#   4. Finds the PDF converter (pdftoppm, from Poppler) for this user. The
#      service runs as SYSTEM, which cannot find it by itself, so its full
#      path goes in the settings file.
#   5. Says whether Ollama answers on this PC (a warning only: the relay
#      keeps asking until Ollama is running).
#   6. Removes an earlier copy of THIS relay (same DEV/PRD name), so two
#      copies never run and split the invoices between them.
#   7. Copies DLA-Relay.exe and DLA-Relay-Service.exe to
#      C:\Program Files\DLA Relay <DEV|PRD>, writes DLA-Relay-Service.xml
#      there with this relay's service id and name, and writes
#      dla-relay-settings.json there (readable by Administrators and SYSTEM
#      only: it holds the token).
#   8. Installs and starts the Windows service (starts with the PC, restarts
#      itself if it stops on an error) and shows the relay's first lines.
#
#   -Uninstall  lists the DLA relays on this PC, asks which one, then stops
#               and removes that service and its folder.
#
# Nothing is opened on this PC's firewall: the relay only calls out to the
# database over HTTPS (port 443) and to Ollama on this PC (127.0.0.1:11434).
#
# Runs on Windows PowerShell 5.1 (built into Windows 10 / 11).
# ============================================================================
param(
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'

$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Files     = @('DLA-Relay.exe', 'DLA-Relay-Service.exe', 'DLA-Relay-Service.xml')
$IdPrefix  = 'DLARelay'

function Say([string]$text, [string]$color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Stop-Here([string]$text) {
    Say ''
    Say ('  NOT INSTALLED: ' + $text) 'Red'
    Say ''
    Read-Host '  Press Enter to close'
    exit 1
}

# ----------------------------------------------------------------------------
# 1. Administrator rights
# ----------------------------------------------------------------------------
$me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args2 = '-NoProfile -ExecutionPolicy Bypass -File "' + $MyInvocation.MyCommand.Path + '"'
    if ($Uninstall) { $args2 += ' -Uninstall' }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args2 -Verb RunAs | Out-Null
    } catch {
        Say 'Administrator rights are needed to install a Windows service. Setup was not run.' 'Red'
        Read-Host 'Press Enter to close'
    }
    exit
}

Clear-Host
Say ''
Say '  ==========================================================' 'Cyan'
Say '   Document Loading Agent - Invoice Relay - Setup' 'Cyan'
Say '  ==========================================================' 'Cyan'
Say ''

# The folder a service's program lives in, read from Windows.
function Get-ServiceFolder([string]$id) {
    $w = Get-CimInstance -ClassName Win32_Service -Filter ("Name='" + $id + "'") -ErrorAction SilentlyContinue
    if ($null -eq $w -or -not $w.PathName) { return $null }
    $exe = $w.PathName.Trim()
    if ($exe.StartsWith('"')) { $exe = $exe.Substring(1, $exe.IndexOf('"', 1) - 1) }
    else { $exe = $exe.Split(' ')[0] }
    return (Split-Path -Parent $exe)
}

# Stops and removes one relay service, then its folder.
function Remove-Relay([string]$id, [string]$folder) {
    $svc = Get-Service -Name $id -ErrorAction SilentlyContinue
    if ($null -ne $svc) {
        Say ('  Removing the relay service ' + $id + '...')
        if ($svc.Status -ne 'Stopped') {
            Stop-Service -Name $id -Force -ErrorAction SilentlyContinue
            try { $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(60)) } catch { }
        }
        $wrapper = $null
        if ($folder) { $wrapper = Join-Path $folder 'DLA-Relay-Service.exe' }
        if ($wrapper -and (Test-Path $wrapper)) {
            & $wrapper uninstall | Out-Null
        } else {
            & sc.exe delete $id | Out-Null
        }
        Start-Sleep -Seconds 2
    }
    if ($folder -and (Test-Path $folder)) {
        Remove-Item -Path $folder -Recurse -Force
    }
}

# ----------------------------------------------------------------------------
# Uninstall: pick one relay from the list
# ----------------------------------------------------------------------------
if ($Uninstall) {
    $relays = @(Get-Service -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -like ($IdPrefix + '-*') } |
                Sort-Object Name)
    if ($relays.Count -eq 0) {
        Say '  There is no DLA relay service on this PC.' 'Yellow'
        Say ''
        Read-Host '  Press Enter to close'
        exit 0
    }
    Say '  DLA relays on this PC:'
    Say ''
    for ($i = 0; $i -lt $relays.Count; $i++) {
        Say ('   ' + ($i + 1) + '.  ' + $relays[$i].DisplayName + '   (' + $relays[$i].Status + ')')
    }
    Say ''
    $pick = (Read-Host '  Number of the relay to remove (Enter = cancel)').Trim()
    $n = 0
    if (-not [int]::TryParse($pick, [ref]$n) -or $n -lt 1 -or $n -gt $relays.Count) {
        Say '  Nothing was removed.' 'Yellow'
        Say ''
        Read-Host '  Press Enter to close'
        exit 0
    }
    $chosen = $relays[$n - 1]
    Remove-Relay $chosen.Name (Get-ServiceFolder $chosen.Name)
    Say ''
    Say ('  Removed: ' + $chosen.DisplayName) 'Green'
    Say ''
    Read-Host '  Press Enter to close'
    exit 0
}

# ----------------------------------------------------------------------------
# The files to install must be next to this script (unzipped).
# ----------------------------------------------------------------------------
foreach ($f in $Files) {
    if (-not (Test-Path (Join-Path $SourceDir $f))) {
        Stop-Here ($f + ' is not in ' + $SourceDir + '. Extract the whole DLA-Relay-Setup zip first, then run Setup-DLA-Relay.cmd from it.')
    }
}

# ----------------------------------------------------------------------------
# 2. DEV or PRD, the database address, the token
# ----------------------------------------------------------------------------
$envTag = (Read-Host '  Which database does this relay serve? Type DEV or PRD').Trim().ToUpper()
if ($envTag -ne 'DEV' -and $envTag -ne 'PRD') {
    Stop-Here 'type DEV or PRD.'
}
Say ''
Say '  Database address: the ORDS address ending in /prd_workspace, for example'
Say '  https://abc1234567890ab-mydatabase.adb.us-chicago-1.oraclecloudapps.com/ords/prd_workspace'
$ordsUrl = (Read-Host '  Database address').Trim().TrimEnd('/')
if (-not $ordsUrl.StartsWith('https://')) {
    Stop-Here 'the database address must start with https://'
}
Say ''
Say '  Relay token: the value of RELAY_TOKEN in DLA_SETTINGS in that database.'
$token = (Read-Host '  Relay token (right-click pastes)').Trim()
if ($token.Length -lt 32) {
    Stop-Here 'that token is too short. Copy the whole value of RELAY_TOKEN again.'
}

# ----------------------------------------------------------------------------
# 3. Check the address and token with the database (stores nothing)
# ----------------------------------------------------------------------------
Say ''
Say '  Checking the address and token with the database...'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$checkUrl = $ordsUrl + '/dla/relay/documents'
$status = $null
try {
    Invoke-RestMethod -Uri $checkUrl -Method Post -Body '{}' -ContentType 'application/json' `
        -Headers @{ 'X-DLA-Relay-Token' = $token } -TimeoutSec 30 -UseBasicParsing | Out-Null
    $status = 200
} catch {
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    if ($null -eq $status) {
        Stop-Here ('this PC could not reach the database over the internet (HTTPS, port 443). ' + $_.Exception.Message)
    }
}
if ($status -eq 401) { Stop-Here 'the database did not accept this token. Copy RELAY_TOKEN again from that database.' }
if ($status -eq 404) { Stop-Here 'the database has no relay at that address. Check that it ends in /prd_workspace and that the DLA is installed there.' }
if ($status -ne 400) { Stop-Here ('the database answered with HTTP ' + $status + ' instead of the expected 400.') }
Say '  The database accepted the token.' 'Green'

# ----------------------------------------------------------------------------
# 4. The PDF converter (pdftoppm) for this user
# ----------------------------------------------------------------------------
$pdftoppm = $null
$wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
if (Test-Path $wingetPackages) {
    $hit = Get-ChildItem -Path $wingetPackages -Directory -Filter '*oppler*' -ErrorAction SilentlyContinue |
           ForEach-Object { Get-ChildItem -Path $_.FullName -Recurse -Filter 'pdftoppm.exe' -ErrorAction SilentlyContinue } |
           Select-Object -First 1
    if ($hit) { $pdftoppm = $hit.FullName }
}
if (-not $pdftoppm) {
    $cmd = Get-Command pdftoppm.exe -ErrorAction SilentlyContinue
    if ($cmd) { $pdftoppm = $cmd.Source }
}
if (-not $pdftoppm) {
    Stop-Here 'the PDF converter (pdftoppm) is not on this PC. Install it with: winget install --id oschwartz10612.Poppler -e   then run this setup again.'
}
Say ('  PDF converter : ' + $pdftoppm) 'Green'

# ----------------------------------------------------------------------------
# 5. Ollama on this PC (warning only)
# ----------------------------------------------------------------------------
try {
    Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 5 -UseBasicParsing | Out-Null
    Say '  Ollama        : answering on 127.0.0.1:11434' 'Green'
} catch {
    Say '  Ollama        : NOT answering now. The relay installs anyway; invoices wait until Ollama is running.' 'Yellow'
}

# ----------------------------------------------------------------------------
# 6. Names, and an earlier copy of this relay goes first
# ----------------------------------------------------------------------------
$watchFolder = 'C:\DLA\inbox'
$ServiceId   = $IdPrefix + '-' + $envTag
$ServiceName = 'DLA Invoice Relay ' + $envTag
$InstallDir  = Join-Path $env:ProgramFiles ('DLA Relay ' + $envTag)
$installedWrapper = Join-Path $InstallDir 'DLA-Relay-Service.exe'

Say ''
Say ('  This relay will be: ' + $ServiceName) 'Cyan'
Say ('  Watched folder    : ' + $watchFolder)
Say ''
Remove-Relay $ServiceId (Get-ServiceFolder $ServiceId)
if (Test-Path $InstallDir) { Remove-Item -Path $InstallDir -Recurse -Force }

# ----------------------------------------------------------------------------
# 7. Files and settings
# ----------------------------------------------------------------------------
Say ('  Installing to ' + $InstallDir + '...')
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
foreach ($f in @('DLA-Relay.exe', 'DLA-Relay-Service.exe')) {
    $to = Join-Path $InstallDir $f
    Copy-Item -Path (Join-Path $SourceDir $f) -Destination $to -Force
    Unblock-File -Path $to -ErrorAction SilentlyContinue
}

$xml = New-Object Xml.XmlDocument
$xml.PreserveWhitespace = $true
$xml.Load((Join-Path $SourceDir 'DLA-Relay-Service.xml'))
$xml.SelectSingleNode('/service/id').InnerText   = $ServiceId
$xml.SelectSingleNode('/service/name').InnerText = $ServiceName
$xml.Save((Join-Path $InstallDir 'DLA-Relay-Service.xml'))

$settings = [ordered]@{
    ords_base_url = $ordsUrl
    relay_token   = $token
    watch_folder  = $watchFolder
    pdftoppm_path = $pdftoppm
}
$settingsPath = Join-Path $InstallDir 'dla-relay-settings.json'
[IO.File]::WriteAllText($settingsPath, ($settings | ConvertTo-Json), (New-Object Text.UTF8Encoding($false)))

# The token is a password for this relay: Administrators and SYSTEM only.
# S-1-5-18 = SYSTEM (the service runs as it), S-1-5-32-544 = Administrators.
& icacls.exe $settingsPath /inheritance:r /grant:r '*S-1-5-18:(R)' '*S-1-5-32-544:(F)' | Out-Null

# ----------------------------------------------------------------------------
# 8. The Windows service
# ----------------------------------------------------------------------------
Say ('  Installing the Windows service "' + $ServiceName + '"...')
& $installedWrapper install | Out-Null
if ($LASTEXITCODE -ne 0) { Stop-Here 'Windows did not accept the service (DLA-Relay-Service.exe install).' }
& $installedWrapper start | Out-Null

$svc = Get-Service -Name $ServiceId -ErrorAction SilentlyContinue
if ($null -eq $svc) { Stop-Here 'the service is not listed after installing it.' }
try { $svc.WaitForStatus('Running', [TimeSpan]::FromSeconds(30)) } catch { }
$svc.Refresh()
if ($svc.Status -ne 'Running') { Stop-Here ('the service did not start (status ' + $svc.Status + ').') }

Start-Sleep -Seconds 6
$log = Join-Path $InstallDir 'DLA-Relay-Service.out.log'
Say ''
Say '  The relay says:' 'Cyan'
if (Test-Path $log) {
    Get-Content -Path $log -Tail 20 | ForEach-Object { Say ('   ' + $_) }
} else {
    Say '   (no log yet)'
}

Say ''
Say '  ==========================================================' 'Green'
Say ('   Done. "' + $ServiceName + '" is running as a Windows service.') 'Green'
Say ('   Its log: ' + $log) 'Green'
Say '  ==========================================================' 'Green'
Say ''
Read-Host '  Press Enter to close'
