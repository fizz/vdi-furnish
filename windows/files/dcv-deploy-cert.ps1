# ACME installation hook. Runs after every issue and renewal.
#
# The ACME client writes PEM files to $Src. DCV does not read its certificate from the
# registry value, whatever its documentation suggests: it reads dcv.pem (the full chain)
# and private\dcv.key under the system profile. Copy them there and restart the server.
param(
  [string]$Src = 'C:\dcv-cert'
)
$dst  = 'C:\Windows\System32\config\systemprofile\AppData\Local\NICE\dcv\private'
# "-chain.pem" is the full chain (leaf plus intermediates); "-chain-only.pem" is the
# intermediates alone and is the wrong file.
$full = Get-ChildItem "$Src\*-chain.pem" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'chain-only' } | Select-Object -First 1
$key  = Get-ChildItem "$Src\*-key.pem"   -ErrorAction SilentlyContinue | Select-Object -First 1
if ($full -and $key) {
  Copy-Item $full.FullName "$dst\dcv.pem" -Force
  Copy-Item $key.FullName  "$dst\dcv.key" -Force
  Restart-Service dcvserver -Force
  Add-Content C:\dcv-deploy.log ((Get-Date).ToString() + ' deployed cert to DCV, restarted dcvserver')
} else {
  Add-Content C:\dcv-deploy.log ((Get-Date).ToString() + " no chain or key found in $Src")
  exit 1
}
