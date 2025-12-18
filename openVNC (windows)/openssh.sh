# Run as Administrator check
if (-not ([bool](New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator))) {
  Write-Error "Run PowerShell as Administrator and re-run this script."
  exit 1
}

Write-Host "=== VNC + OpenSSH automated setup (Windows host) ===" -ForegroundColor Cyan

# --- Inputs ---
$vncPassPlain = Read-Host "Enter desired VNC password (or press Enter to generate a strong random password)"
if ([string]::IsNullOrWhiteSpace($vncPassPlain)) {
  $vncPassPlain = ([System.Web.Security.Membership]::GeneratePassword(14,3)) -replace '[^a-zA-Z0-9]','A'
  Write-Host "Generated VNC password:" -NoNewline; Write-Host " $vncPassPlain" -ForegroundColor Yellow
}

$pubKey = Read-Host "Paste your OpenSSH public key (e.g. ssh-ed25519 AAAA... user@host) or press Enter to skip (you can add it later)"
$restrictCIDR = Read-Host "Restrict VNC firewall rule to a source CIDR (e.g., 203.0.113.0/24) or press Enter to allow ANY (not recommended)"

# --- Helper ---
function Backup-RegistryKey($keyPath,$outFile) {
  try {
    reg export $keyPath $outFile /y > $null 2>&1
    return $true
  } catch {
    return $false
  }
}

# --- 1) Install TightVNC (try winget, choco, then fallback MSI) ---
$installedVNC = $false
Write-Host "`n[1] Installing TightVNC..." -ForegroundColor Cyan
if (Get-Command winget -ErrorAction SilentlyContinue) {
  try { winget install --id TightVNC.TightVNC -e --silent --accept-package-agreements --accept-source-agreements; $installedVNC = $true } catch {}
}
if (-not $installedVNC) {
  if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..." -ForegroundColor DarkCyan
    Set-ExecutionPolicy Bypass -Scope Process -Force
    iex ((New-Object Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
  }
  if (Get-Command choco -ErrorAction SilentlyContinue) {
    try { choco install tightvnc -y --no-progress; $installedVNC = $true } catch {}
  }
}
if (-not $installedVNC) {
  Write-Host "Falling back to direct download (may need to update the URL if version changes)..." -ForegroundColor DarkCyan
  $tmp = "$env:TEMP\tightvnc_installer.msi"
  $url = "https://www.tightvnc.com/download/2.8.63/tightvnc-2.8.63-gpl-setup-64bit.msi"
  Invoke-WebRequest -Uri $url -OutFile $tmp -UseBasicParsing
  Start-Process msiexec.exe -ArgumentList "/i `"$tmp`" /qn /norestart" -Wait
  Remove-Item $tmp -Force -ErrorAction SilentlyContinue
  $installedVNC = $true
}
if (-not $installedVNC) { Write-Error "TightVNC installation failed. Install manually and re-run."; exit 2 }
Write-Host "TightVNC installed (or present)." -ForegroundColor Green

# --- 2) Install & configure OpenSSH Server (for tunneling) ---
Write-Host "`n[2] Ensuring OpenSSH Server is installed and running..." -ForegroundColor Cyan
$cap = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'
if ($cap -and $cap.State -ne 'Installed') {
  try { Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop; Write-Host "OpenSSH installed." -ForegroundColor Green } catch { Write-Warning "Could not install OpenSSH via capability. Please install via Optional Features." }
}
if (Get-Service -Name sshd -ErrorAction SilentlyContinue) {
  Set-Service -Name sshd -StartupType Automatic
  try { Start-Service sshd -ErrorAction Stop; Write-Host "sshd started." -ForegroundColor Green } catch { Write-Warning "Could not start sshd automatically." }
} else {
  Write-Warning "sshd service not found. Ensure OpenSSH Server is installed."
}

# --- 3) Create local 'vnc' user (if not exists) and configure SSH keys ---
Write-Host "`n[3] Creating local account 'vnc' and installing your public key (if provided)..." -ForegroundColor Cyan
$vncUser = 'vnc'
if (-not (Get-LocalUser -Name $vncUser -ErrorAction SilentlyContinue)) {
  # create a random secure password for the account
  $plain = [System.Web.Security.Membership]::GeneratePassword(16,4) -replace '[^a-zA-Z0-9]','A'
  $secure = ConvertTo-SecureString $plain -AsPlainText -Force
  New-LocalUser -Name $vncUser -FullName "VNC SSH User" -Password $secure -PasswordNeverExpires -UserMayNotChangePassword
  Add-LocalGroupMember -Group "Users" -Member $vncUser
  Write-Host "Created user 'vnc' with a generated password (stored only in this session). Use SSH key for access." -ForegroundColor Green
} else {
  Write-Host "User 'vnc' already exists." -ForegroundColor DarkCyan
}

if ($pubKey -and $pubKey.Trim() -ne '') {
  $sshDir = "C:\Users\$vncUser\.ssh"
  if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory -Path $sshDir -Force | Out-Null }
  $authFile = Join-Path $sshDir 'authorized_keys'
  $pubKey.Trim() | Out-File -FilePath $authFile -Encoding ASCII -Append
  # Set permissions: user own only and Administrators full control
  icacls $sshDir /inheritance:r | Out-Null
  icacls $authFile /grant "$vncUser:F" /grant "Administrators:F" /c | Out-Null
  Write-Host "Public key installed to $authFile" -ForegroundColor Green
} else {
  Write-Host "No public key provided; you can add one later to C:\Users\vnc\.ssh\authorized_keys" -ForegroundColor Yellow
}

# Ensure sshd_config allows PubkeyAuthentication
$sshdCfg = "$env:ProgramData\ssh\sshd_config"
if (Test-Path $sshdCfg) {
  (Get-Content $sshdCfg) | ForEach-Object {
    if ($_ -match '^\s*#?\s*PubkeyAuthentication') { "PubkeyAuthentication yes" }
    elseif ($_ -match '^\s*#?\s*PasswordAuthentication') { "PasswordAuthentication no" }
    else { $_ }
  } | Set-Content $sshdCfg
  Restart-Service sshd -ErrorAction SilentlyContinue
  Write-Host "sshd configured for key auth and restarted." -ForegroundColor Green
}

# --- 4) Firewall rules ---
Write-Host "`n[4] Creating firewall rules for SSH (22) and VNC (5900) ..." -ForegroundColor Cyan
function New-IfMissingFirewallRule($name,$port,$proto='TCP',$remoteAddr=$null) {
  if (-not (Get-NetFirewallRule -DisplayName $name -ErrorAction SilentlyContinue)) {
    if ($remoteAddr) {
      New-NetFirewallRule -DisplayName $name -Direction Inbound -LocalPort $port -Protocol $proto -Action Allow -Profile Any -RemoteAddress $remoteAddr
    } else {
      New-NetFirewallRule -DisplayName $name -Direction Inbound -LocalPort $port -Protocol $proto -Action Allow -Profile Any
    }
    Write-Host "Firewall rule created: $name" -ForegroundColor Green
  } else {
    Write-Host "Firewall rule exists: $name" -ForegroundColor DarkCyan
  }
}
New-IfMissingFirewallRule -name "Allow SSH (22)" -port 22
if ($restrictCIDR -and $restrictCIDR.Trim() -ne '') { New-IfMissingFirewallRule -name "Allow VNC (5900)" -port 5900 -remoteAddr $restrictCIDR } else { New-IfMissingFirewallRule -name "Allow VNC (5900)" -port 5900 }

# --- 5) Configure TightVNC service and set password (best-effort, with backups) ---
Write-Host "`n[5] Attempting to configure TightVNC service and set its password (best-effort)..." -ForegroundColor Cyan

# Backup relevant registry nodes (both 64-bit & Wow6432Node)
$regPaths = @("HKLM\SOFTWARE\TightVNC\Server","HKLM\SOFTWARE\WOW6432Node\TightVNC\Server")
foreach ($p in $regPaths) {
  $bk = "$env:ProgramData\TightVNC-reg-backup-$(Get-Date -Format yyyyMMddHHmmss).reg"
  if (Backup-RegistryKey $p $bk) { Write-Host "Backed up $p -> $bk" -ForegroundColor Green }
}

# Try to find TightVNC bin directory
$tvnBin = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "tvnserver.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
if ($tvnBin) {
  $installDir = $tvnBin.Directory.FullName
  Write-Host "TightVNC found at $installDir" -ForegroundColor DarkCyan

  # Try to register service if not present (typical flag)
  try {
    & "$installDir\tvnserver.exe" -install
    Start-Sleep -Seconds 1
    Set-Service -Name tvnserver -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service -Name tvnserver -ErrorAction SilentlyContinue
    Write-Host "TightVNC service registered/started (if installer supports it)." -ForegroundColor Green
  } catch {}

  # Try to find tvnpasswd utility and use it if present
  $tvnPassUtil = Get-ChildItem $installDir -Filter "tvnpasswd.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($tvnPassUtil) {
    Write-Host "Found tvnpasswd at $($tvnPassUtil.FullName). Attempting to set password..." -ForegroundColor DarkCyan
    try {
      # Many tvnpasswd versions accept input or args; attempt common variants safely
      # Variant A: tvnpasswd.exe -setpassword <password> (tries)
      & $tvnPassUtil.FullName "-setpassword" $vncPassPlain
      # Variant B (pipe) - for some versions:
      # $vncPassPlain | & $tvnPassUtil.FullName -service
      Write-Host "tvnpasswd invoked (check TightVNC Server configuration to confirm password set)." -ForegroundColor Green
    } catch {
      Write-Warning "tvnpasswd failed or did not accept these arguments; please set the password manually (instructions below)."
    }
  } else {
    Write-Warning "tvnpasswd utility not found in the TightVNC folder; automatic password set may not be possible."
  }

} else {
  Write-Warning "Could not locate TightVNC binaries automatically. You may need to set the password manually in the GUI."
}

# If automatic method likely failed, give instructions
Write-Host ""
Write-Host "If the VNC password is not configured automatically, do this manually:" -ForegroundColor Yellow
Write-Host "  1) Open 'TightVNC Server - Configuration' (Start Menu or C:\Program Files\TightVNC\)." -ForegroundColor White
Write-Host "  2) Under Authentication, set the Primary password and click Apply." -ForegroundColor White
Write-Host "  3) Enable 'Register TightVNC Server as a system service' to make it available at logon." -ForegroundColor White
Write-Host ""
Write-Host "I also backed up possible TightVNC registry keys (search for files named 'TightVNC-reg-backup-*.reg' in C:\\ProgramData)." -ForegroundColor Green

# --- 6) Report helpful SSH tunnel command
$hostFQDN = (hostname)
Write-Host "`n=== Complete (phase 1) ===" -ForegroundColor Green
Write-Host "To connect securely from your client machine using your SSH key:" -ForegroundColor Cyan
Write-Host "  ssh -i /path/to/your_private_key -L 5900:localhost:5900 $vnc@$hostFQDN" -ForegroundColor Yellow
Write-Host "Then open your VNC client and connect to localhost:5900." -ForegroundColor Green

Write-Host ""
Write-Host "If you'd like, I can now attempt a targeted automatic password-set routine (try additional tvnpasswd flags, write registry in TightVNC format, or switch to TigerVNC which is easier to script). Tell me which you prefer." -ForegroundColor Cyan