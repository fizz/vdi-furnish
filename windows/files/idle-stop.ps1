# Stop this instance when no work is running on it and nobody is attached.
#
# The gate is the work, not a timer. A batch can run for tens of minutes with nobody
# watching, and an idle timer would kill it mid-flight. Ask the thing that does the work:
# $BusyCheck is a command that prints how many units of work are in flight.
#
# Unknown is busy. If the engine cannot be asked, or DCV cannot be asked, the answer is
# "busy", never "idle".
#
# Two guards:
#   - boot grace: never stop within $GraceMinutes of boot, or a start stops itself again
#     before anyone finishes connecting.
#   - consecutive idle: require $IdleChecksToStop samples in a row, so one failed poll
#     does not stop a live session.
#
# Dry run until $ArmedFile exists. It decides and logs but stops nothing, so the decision
# can be read for a day before it is trusted.
#
# Run it as the login user, not SYSTEM, if $BusyCheck goes through wsl.exe: wsl.exe
# refuses to run as SYSTEM.
param(
  [int]$GraceMinutes     = 20,
  [int]$IdleChecksToStop = 6,        # x a 5-minute schedule = 30 minutes
  [string]$BusyCheck     = 'wsl.exe -d Ubuntu -u root -- bash -lc "docker ps -q --filter label=com.docker.compose.service=lab | wc -l"',
  [string]$WslDistro     = 'Ubuntu',  # set '' if $BusyCheck does not use WSL
  [string]$Root          = 'C:\ProgramData\vdi-furnish'
)

$ErrorActionPreference = 'Continue'
$Log       = Join-Path $Root 'logs\idle-stop.log'
$StateFile = Join-Path $Root 'idle-stop.state'
$ArmedFile = Join-Path $Root 'idle-stop-armed'
$Dcv       = 'C:\Program Files\NICE\DCV\Server\bin\dcv.exe'
New-Item -ItemType Directory -Force -Path (Split-Path $Log) | Out-Null

# Append with a retry and an explicit share mode. A log shipper that tails this file holds
# a handle on it, and Add-Content's write handle cannot coexist with that. Under
# $ErrorActionPreference = 'Continue' the failure is a silent skip with exit 0: the gate
# keeps deciding correctly and records none of it.
function Rec([hashtable]$o) {
  $o['ts'] = (Get-Date).ToUniversalTime().ToString('o')
  $line = ($o | ConvertTo-Json -Compress)
  for ($i = 0; $i -lt 10; $i++) {
    try {
      $fs = [IO.File]::Open($Log, 'Append', 'Write', 'ReadWrite')
      $sw = New-Object IO.StreamWriter($fs)
      $sw.WriteLine($line); $sw.Flush(); $sw.Dispose(); $fs.Dispose()
      return
    } catch { Start-Sleep -Milliseconds 200 }
  }
  Write-EventLog -LogName Application -Source Application -EventId 1001 `
    -EntryType Warning -Message "idle-stop could not append: $line" -ErrorAction SilentlyContinue
}
function Busy([hashtable]$o) {
  for ($i = 0; $i -lt 10; $i++) {
    try { [IO.File]::WriteAllText($StateFile, '0'); break } catch { Start-Sleep -Milliseconds 200 }
  }
  Rec $o
  exit 0
}

# Who am I, from IMDSv2.
try {
  $tok    = Invoke-RestMethod -Method Put -Uri 'http://169.254.169.254/latest/api/token' `
              -Headers @{ 'X-aws-ec2-metadata-token-ttl-seconds' = '120' } -TimeoutSec 5
  $h      = @{ 'X-aws-ec2-metadata-token' = $tok }
  $iid    = Invoke-RestMethod -Uri 'http://169.254.169.254/latest/meta-data/instance-id' -Headers $h -TimeoutSec 5
  $az     = Invoke-RestMethod -Uri 'http://169.254.169.254/latest/meta-data/placement/availability-zone' -Headers $h -TimeoutSec 5
  $region = $az.Substring(0, $az.Length - 1)
} catch { Busy @{ event = 'imds_failed'; error = $_.Exception.Message; action = 'no stop' } }

$up = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
if ($up.TotalMinutes -lt $GraceMinutes) {
  Busy @{ event = 'within_boot_grace'; uptime_min = [math]::Round($up.TotalMinutes, 1) }
}

# Is work in flight? Do not wake what you poll: asking a stopped WSL distro starts it, and
# a poll every five minutes would then keep the VM alive to be told it is idle.
$work = $null
try {
  if ($WslDistro -ne '') {
    $running = (& wsl.exe -l --running -q 2>&1 | Out-String)
    if ($running -notmatch [regex]::Escape($WslDistro)) { $work = 0 }
  }
  if ($null -eq $work) {
    $o = (Invoke-Expression $BusyCheck 2>&1 | Out-String).Trim()
    if ($o -match '(\d+)\s*$') { $work = [int]$Matches[1] }
  }
} catch { }
if ($null -eq $work) { Busy @{ event = 'work_query_failed'; action = 'treated as busy' } }
if ($work -gt 0)     { Busy @{ event = 'work_in_flight'; units = $work } }

# Is a person attached? Someone reading results is using the desktop.
$clients = $null
$out = (& $Dcv list-connections console 2>&1 | Out-String)
if ($LASTEXITCODE -eq 0) { $clients = ([regex]::Matches($out, 'Connected client')).Count }
if ($null -eq $clients) { Busy @{ event = 'dcv_query_failed'; action = 'treated as busy' } }
if ($clients -gt 0)     { Busy @{ event = 'client_attached'; clients = $clients } }

# Idle: count consecutive samples.
$n = 0
if (Test-Path $StateFile) { $v = (Get-Content $StateFile -Raw).Trim(); if ($v -match '^\d+$') { $n = [int]$v } }
$n++
Set-Content -Path $StateFile -Value $n
$armed = Test-Path $ArmedFile

if ($n -lt $IdleChecksToStop) { Rec @{ event = 'idle'; consecutive = $n; needed = $IdleChecksToStop; armed = $armed }; exit 0 }
if (-not $armed) { Rec @{ event = 'would_stop'; consecutive = $n; instance = $iid; armed = $false }; exit 0 }

Rec @{ event = 'stopping'; consecutive = $n; instance = $iid; region = $region }
$r = (& aws ec2 stop-instances --instance-ids $iid --region $region 2>&1 | Out-String)
Rec @{ event = 'stop_issued'; result = $r.Trim() }
Set-Content -Path $StateFile -Value 0
