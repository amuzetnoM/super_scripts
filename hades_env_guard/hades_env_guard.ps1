#!/usr/bin/env pwsh
<#
.SYNOPSIS
    HADES Environment Guard - Universal Codebase Secret Scanner and Manager

.DESCRIPTION
    Scans any codebase for hardcoded secrets, credentials, and API keys.
    Interactively guides user through sanitization and secure storage via GitHub Secrets.

.PARAMETER DryRun
    Preview mode - shows what would be done without making changes

.EXAMPLE
    .\hades_env_guard.ps1
    .\hades_env_guard.ps1 -DryRun
#>

param(
    [switch]$DryRun
)

$script:Path = ""

# ══════════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ══════════════════════════════════════════════════════════════════════════════

$script:FoundSecrets = @()

# Pre-compile regex patterns to avoid PowerShell parsing issues
$script:SecretPatterns = @(
    @{ Name = "Password Field"; Pattern = [regex]::new('(?i)(password|passwd|pwd)\s*[=:]\s*["'']?([^"''\s]{4,})["'']?') },
    @{ Name = "API Key"; Pattern = [regex]::new('(?i)(api[_-]?key|apikey)\s*[=:]\s*["'']?(\w{16,})["'']?') },
    @{ Name = "Secret Key"; Pattern = [regex]::new('(?i)(secret[_-]?key|client[_-]?secret)\s*[=:]\s*["'']?(\w{16,})["'']?') },
    @{ Name = "Access Token"; Pattern = [regex]::new('(?i)(access[_-]?token|auth[_-]?token|bearer)\s*[=:]\s*["'']?([\w.\-]{20,})["'']?') },
    @{ Name = "Private Key"; Pattern = [regex]::new('(?i)-----BEGIN\s+(RSA\s+)?PRIVATE\s+KEY-----') },
    @{ Name = "AWS Key"; Pattern = [regex]::new('(?i)(aws[_-]?access[_-]?key[_-]?id|aws[_-]?secret)\s*[=:]\s*["'']?(\w{16,})["'']?') },
    @{ Name = "Telegram Token"; Pattern = [regex]::new('(?i)(telegram[_-]?bot[_-]?token|tg[_-]?token)\s*[=:]\s*["'']?(\d+:[\w\-]{30,})["'']?') },
    @{ Name = "GitHub Token"; Pattern = [regex]::new('(?i)(github[_-]?token|gh[_-]?token)\s*[=:]\s*["'']?(ghp_\w{30,})["'']?') },
    @{ Name = "Login/Account ID"; Pattern = [regex]::new('(?i)(login|account[_-]?id|user[_-]?id)\s*[=:]\s*["'']?(\d{6,})["'']?') },
    @{ Name = "Server Config"; Pattern = [regex]::new('(?i)(server)\s*[=:]\s*["'']?([\w\-.]+ \d+)["'']?') },
    @{ Name = "Generic Secret"; Pattern = [regex]::new('(?i)(secret|credential|token)\s*[=:]\s*["'']([^"'']{8,})["'']') }
)

$script:ExcludedDirs = @(
    '.git', 'node_modules', '__pycache__', 'venv', 'venv312', '.venv',
    'dist', 'build', '.next', 'coverage', '.pytest_cache', '.mypy_cache',
    'egg-info', '.eggs', 'target', 'bin', 'obj', 'packages'
)

$script:ExcludedFiles = @(
    '*.exe', '*.dll', '*.so', '*.dylib', '*.pyc', '*.pyo',
    '*.jpg', '*.jpeg', '*.png', '*.gif', '*.ico', '*.svg',
    '*.pdf', '*.doc', '*.docx', '*.zip', '*.tar', '*.gz',
    '*.mp3', '*.mp4', '*.wav', '*.avi', '*.mov',
    '*.woff', '*.woff2', '*.ttf', '*.eot', '*.otf',
    'package-lock.json', 'yarn.lock', 'poetry.lock'
)

$script:SensitiveFiles = @(
    '*.json', '*.yaml', '*.yml', '*.toml', '*.ini', '*.cfg',
    '*.conf', '*.config', '*.env', '*.env.*', '.env*',
    '*.properties', '*.xml', '*.py', '*.js', '*.ts', '*.ps1'
)

# ══════════════════════════════════════════════════════════════════════════════
# DISPLAY FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

function Write-Banner {
    # Try to set console code page and output encoding to UTF-8 so Unicode box-drawing and block characters render correctly
    try {
        chcp 65001 > $null 2>&1
    } catch {}

    try {
        [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
    }
    catch {
        # Ignore if not supported in this environment; fallback below will use ASCII-only banner
    }

    $banner = @"
    $banner = @"
                          ;                                
                          ED.                              
                          E#Wi                 ,;         .
  .    .                  E###G.             f#i         ;W
  Di   Dt              .. E#fD#W;          .E#t         f#E
  E#i  E#i            ;W, E#t t##L        i#W,        .E#f 
  E#t  E#t           j##, E#t  .E#K,     L#D.        iWW;  
  E#t  E#t          G###, E#t    j##f  :K#Wfff;     L##Lffi
  E########f.     :E####, E#t    :E#K: i##WLLLLt   tLLG##L 
  E#j..K#j...    ;W#DG##, E#t   t##L    .E#L         ,W#i  
  E#t  E#t      j###DW##, E#t .D#W;       f#E:      j#E.   
  E#t  E#t     G##i,,G##, E#tiW#G.         ,WW;   .D#j     
  f#t  f#t   :K#K:   L##, E#K##i            .D#; ,WK,      
   ii   ii  ;##D.    L##, E##D.               tt EG.       
            ,,,      .,,  E#t                    ,         
                          L:                                
"@

    # If console encoding doesn't support the Unicode characters above they may appear mangled.
    # Provide an ASCII fallback that matches README visually when necessary.
    $encodingName = ""
    try { $encodingName = [Console]::OutputEncoding.WebName } catch { $encodingName = "unknown" }

    if ($encodingName -and $encodingName -notlike "*utf*" ) {
        $banner = @"
  +-------------------------------------------------------------+
  |   H A D E S   E N V I R O N M E N T   G U A R D   v2.0     |
  +-------------------------------------------------------------+
  |  The gatekeeper of your secrets. A powerful, interactive   |
  |  PowerShell tool that hunts down hardcoded credentials     |
  |  in any codebase and helps you secure them properly.       |
  +-------------------------------------------------------------+
"@
    }

    Write-Host $banner -ForegroundColor Cyan
    Write-Host "  Universal Codebase Secret Scanner and Manager" -ForegroundColor Yellow
    Write-Host "        ═══════════════════════════════════════════════════=" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Section {
    param([string]$Title, [string]$Color = "Cyan")
    Write-Host ""
    Write-Host "  +-----------------------------------------------------------------+" -ForegroundColor $Color
    Write-Host "  |  $($Title.PadRight(61))|" -ForegroundColor $Color
    Write-Host "  +-----------------------------------------------------------------+" -ForegroundColor $Color
    Write-Host ""
}

function Write-OK { param([string]$Message) Write-Host "  [OK] $Message" -ForegroundColor Green }
function Write-Warn { param([string]$Message) Write-Host "  [!!] $Message" -ForegroundColor Yellow }
function Write-Err { param([string]$Message) Write-Host "  [XX] $Message" -ForegroundColor Red }
function Write-Nfo { param([string]$Message) Write-Host "  [ii] $Message" -ForegroundColor Cyan }
function Write-Step { param([string]$Message) Write-Host "  [>>] $Message" -ForegroundColor White }
function Write-Secret { param([string]$Message) Write-Host "  [**] $Message" -ForegroundColor Magenta }

function Get-MaskedValue {
    param([string]$Value, [int]$ShowChars = 3)
    if ([string]::IsNullOrEmpty($Value)) { return "***" }
    if ($Value.Length -le ($ShowChars * 2)) {
        return "*" * $Value.Length
    }
    return $Value.Substring(0, $ShowChars) + ("*" * ($Value.Length - $ShowChars * 2)) + $Value.Substring($Value.Length - $ShowChars)
}

# ══════════════════════════════════════════════════════════════════════════════
# SCANNING FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

function Test-ShouldExclude {
    param([string]$FilePath)
    
    foreach ($dir in $script:ExcludedDirs) {
        if ($FilePath -like "*\$dir\*") { return $true }
    }
    
    $fileName = Split-Path $FilePath -Leaf
    foreach ($pattern in $script:ExcludedFiles) {
        if ($fileName -like $pattern) { return $true }
    }
    
    return $false
}

function Test-IsSensitiveFile {
    param([string]$FilePath)
    
    $fileName = Split-Path $FilePath -Leaf
    foreach ($pattern in $script:SensitiveFiles) {
        if ($fileName -like $pattern) { return $true }
    }
    return $false
}

function Find-SecretsInFile {
    param([string]$FilePath)
    
    $secrets = @()
    
    try {
        $lines = Get-Content $FilePath -ErrorAction Stop
        $lineNum = 0
        
        foreach ($line in $lines) {
            $lineNum++
            
            # Skip comments and empty lines
            if ($line -match '^\s*(#|//|/\*|\*|<!--)' -or [string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            
            # Skip lines with placeholder values
            if ($line -match 'your[_-]?(key|token|secret|password)|placeholder|example|xxx+|TODO|CHANGEME|YOUR_') {
                continue
            }
            
            foreach ($patternInfo in $script:SecretPatterns) {
                $regex = $patternInfo.Pattern
                $match = $regex.Match($line)
                
                if ($match.Success) {
                    $matchValue = if ($match.Groups.Count -gt 2) { $match.Groups[2].Value } else { $match.Groups[1].Value }
                    
                    # Skip if looks like a placeholder
                    if ($matchValue -match '^(your|example|test|demo|placeholder|xxx|changeme|todo)') {
                        continue
                    }
                    
                    # Skip very short matches
                    if ($matchValue.Length -lt 4) { continue }
                    
                    $secrets += @{
                        File = $FilePath
                        Line = $lineNum
                        Type = $patternInfo.Name
                        Value = $matchValue
                        Context = $line.Trim()
                    }
                }
            }
        }
    }
    catch {
        # Skip files that cannot be read
    }
    
    return $secrets
}

function Start-CodebaseScan {
    param([string]$RootPath)
    
    Write-Section "SCANNING CODEBASE" "Yellow"
    Write-Nfo "Target: $RootPath"
    Write-Host ""
    
    $files = Get-ChildItem -Path $RootPath -Recurse -File -ErrorAction SilentlyContinue
    $totalFiles = $files.Count
    $scannedFiles = 0
    $sensitiveFiles = 0
    
    Write-Step "Found $totalFiles files to analyze..."
    Write-Host ""
    
    $progressWidth = 50
    
    foreach ($file in $files) {
        $scannedFiles++
        
        # Progress bar
        $percent = [math]::Round(($scannedFiles / $totalFiles) * 100)
        $filled = [math]::Round(($percent / 100) * $progressWidth)
        $empty = $progressWidth - $filled
        $bar = ("#" * $filled) + ("-" * $empty)
        Write-Host "`r  [$bar] $percent% ($scannedFiles/$totalFiles)" -NoNewline -ForegroundColor Cyan
        
        if (Test-ShouldExclude $file.FullName) { continue }
        if (-not (Test-IsSensitiveFile $file.FullName)) { continue }
        
        $sensitiveFiles++
        $foundSecrets = Find-SecretsInFile -FilePath $file.FullName
        
        foreach ($secret in $foundSecrets) {
            $script:FoundSecrets += $secret
        }
    }
    
    Write-Host ""
    Write-Host ""
    Write-OK "Scanned $sensitiveFiles sensitive files out of $totalFiles total"
    
    return $script:FoundSecrets
}

# ══════════════════════════════════════════════════════════════════════════════
# REPORTING FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

function Show-SecretsReport {
    param([array]$Secrets)
    
    Write-Section "SECRETS DETECTED" "Red"
    
    if ($Secrets.Count -eq 0) {
        Write-OK "No hardcoded secrets detected! Your codebase is clean."
        return
    }
    
    Write-Warn "Found $($Secrets.Count) potential secrets/credentials:"
    Write-Host ""
    
    $groupedByFile = $Secrets | Group-Object -Property File
    
    $secretIndex = 1
    foreach ($group in $groupedByFile) {
        $relativePath = $group.Name.Replace($Path, "").TrimStart("\", "/")
        Write-Host "  FILE: " -NoNewline -ForegroundColor Yellow
        Write-Host $relativePath -ForegroundColor White
        
        foreach ($secret in $group.Group) {
            $maskedValue = Get-MaskedValue -Value $secret.Value
            Write-Host "     +-- " -NoNewline -ForegroundColor DarkGray
            Write-Host "[$secretIndex] " -NoNewline -ForegroundColor Cyan
            Write-Host "$($secret.Type)" -NoNewline -ForegroundColor Magenta
            Write-Host " (Line $($secret.Line)): " -NoNewline -ForegroundColor DarkGray
            Write-Host $maskedValue -ForegroundColor Red
            $secretIndex++
        }
        Write-Host ""
    }
}

# ══════════════════════════════════════════════════════════════════════════════
# SANITIZATION FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

function Get-PlaceholderForType {
    param([string]$Type)
    
    switch -Regex ($Type) {
        "Password" { return "YOUR_PASSWORD_HERE" }
        "API Key" { return "YOUR_API_KEY_HERE" }
        "Secret Key" { return "YOUR_SECRET_KEY_HERE" }
        "Access Token" { return "YOUR_ACCESS_TOKEN_HERE" }
        "AWS" { return "YOUR_AWS_KEY_HERE" }
        "Database" { return "YOUR_DATABASE_URL_HERE" }
        "Telegram" { return "YOUR_TELEGRAM_TOKEN_HERE" }
        "Discord" { return "YOUR_DISCORD_TOKEN_HERE" }
        "GitHub" { return "YOUR_GITHUB_TOKEN_HERE" }
        "Login|Account" { return "YOUR_ACCOUNT_ID_HERE" }
        "Server" { return "YOUR_SERVER_HERE" }
        default { return "YOUR_SECRET_HERE" }
    }
}

function Get-EnvVarName {
    param([string]$Type, [string]$Context)
    
    # Try to extract variable name from context
    $varNamePattern = [regex]::new('([A-Z][A-Z0-9_]{2,})\s*[=:]')
    $match = $varNamePattern.Match($Context.ToUpper())
    if ($match.Success) {
        return $match.Groups[1].Value
    }
    
    switch -Regex ($Type) {
        "Password" { return "SECRET_PASSWORD" }
        "API Key" { return "API_KEY" }
        "Secret Key" { return "SECRET_KEY" }
        "Access Token" { return "ACCESS_TOKEN" }
        "AWS" { return "AWS_SECRET_KEY" }
        "Database" { return "DATABASE_URL" }
        "Telegram" { return "TELEGRAM_BOT_TOKEN" }
        "Discord" { return "DISCORD_TOKEN" }
        "GitHub" { return "GITHUB_TOKEN" }
        "Login|Account" { return "ACCOUNT_ID" }
        "Server" { return "SERVER_CONFIG" }
        default { return "SECRET_VALUE" }
    }
}

function Start-Sanitization {
    param([array]$Secrets)
    
    Write-Section "SANITIZATION OPTIONS" "Green"
    
    if ($Secrets.Count -eq 0) {
        Write-Nfo "No secrets to sanitize."
        return @()
    }
    
    Write-Host "  Choose how to handle detected secrets:" -ForegroundColor White
    Write-Host ""
    Write-Host "    [1] " -NoNewline -ForegroundColor Cyan
    Write-Host "Auto-sanitize ALL - Replace with placeholders and store in GitHub Secrets" -ForegroundColor White
    Write-Host "    [2] " -NoNewline -ForegroundColor Cyan
    Write-Host "Interactive mode - Review each secret individually" -ForegroundColor White
    Write-Host "    [3] " -NoNewline -ForegroundColor Cyan
    Write-Host "Export only - Create .env file without modifying source files" -ForegroundColor White
    Write-Host "    [4] " -NoNewline -ForegroundColor Cyan
    Write-Host "Skip sanitization" -ForegroundColor White
    Write-Host ""
    
    $choice = Read-Host "  Select option (1-4)"
    
    $secretsToStore = @()
    
    switch ($choice) {
        "1" {
            Write-Host ""
            Write-Step "Auto-sanitizing all secrets..."
            
            foreach ($secret in $Secrets) {
                $envName = Get-EnvVarName -Type $secret.Type -Context $secret.Context
                $placeholder = Get-PlaceholderForType -Type $secret.Type
                
                $secretsToStore += @{
                    Name = $envName
                    Value = $secret.Value
                    Type = $secret.Type
                    File = $secret.File
                    Placeholder = $placeholder
                }
                
                if (-not $DryRun) {
                    # Replace in file
                    $content = Get-Content $secret.File -Raw
                    $escapedValue = [regex]::Escape($secret.Value)
                    $newContent = $content -replace $escapedValue, $placeholder
                    Set-Content -Path $secret.File -Value $newContent -NoNewline
                }
                
                Write-OK "Sanitized: $($secret.Type) in $(Split-Path $secret.File -Leaf)"
            }
        }
        "2" {
            Write-Host ""
            $index = 1
            foreach ($secret in $Secrets) {
                Write-Host ""
                Write-Secret "Secret $index of $($Secrets.Count)"
                Write-Host "     File: $(Split-Path $secret.File -Leaf) (Line $($secret.Line))" -ForegroundColor Gray
                Write-Host "     Type: $($secret.Type)" -ForegroundColor Magenta
                Write-Host "     Value: $(Get-MaskedValue $secret.Value)" -ForegroundColor Red
                Write-Host ""
                Write-Host "     [S] Sanitize  [K] Keep  [I] Ignore" -ForegroundColor Cyan
                
                $action = Read-Host "     Action"
                
                if ($action -eq "S" -or $action -eq "s") {
                    $envName = Get-EnvVarName -Type $secret.Type -Context $secret.Context
                    $customName = Read-Host "     Env var name [$envName]"
                    if (-not [string]::IsNullOrWhiteSpace($customName)) { $envName = $customName }
                    
                    $placeholder = Get-PlaceholderForType -Type $secret.Type
                    
                    $secretsToStore += @{
                        Name = $envName
                        Value = $secret.Value
                        Type = $secret.Type
                        File = $secret.File
                        Placeholder = $placeholder
                    }
                    
                    if (-not $DryRun) {
                        $content = Get-Content $secret.File -Raw
                        $escapedValue = [regex]::Escape($secret.Value)
                        $newContent = $content -replace $escapedValue, $placeholder
                        Set-Content -Path $secret.File -Value $newContent -NoNewline
                    }
                    
                    Write-OK "Marked for sanitization: $envName"
                }
                $index++
            }
        }
        "3" {
            Write-Host ""
            Write-Step "Creating .env export file..."
            
            foreach ($secret in $Secrets) {
                $envName = Get-EnvVarName -Type $secret.Type -Context $secret.Context
                $secretsToStore += @{
                    Name = $envName
                    Value = $secret.Value
                    Type = $secret.Type
                    File = $secret.File
                }
            }
        }
        default {
            Write-Nfo "Skipping sanitization."
            return @()
        }
    }
    
    return $secretsToStore
}

# ══════════════════════════════════════════════════════════════════════════════
# STORAGE FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

function Save-ToEnvFile {
    param([array]$Secrets, [string]$OutputPath)
    
    $envFile = Join-Path $OutputPath ".env.secrets"
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    
    $content = @"
# ══════════════════════════════════════════════════════════════════════════════
# SECRET GUARDIAN - Auto-generated Environment File
# Generated: $timestamp
# ══════════════════════════════════════════════════════════════════════════════
# WARNING: This file contains sensitive credentials!
# - Add to .gitignore immediately
# - Never commit to version control
# - Store securely using GitHub Secrets for production
# ══════════════════════════════════════════════════════════════════════════════

"@
    
    $groupedSecrets = $Secrets | Group-Object -Property Type
    
    foreach ($group in $groupedSecrets) {
        $content += "`n# $($group.Name)`n"
        foreach ($secret in $group.Group) {
            $content += "$($secret.Name)=$($secret.Value)`n"
        }
    }
    
    if (-not $DryRun) {
        Set-Content -Path $envFile -Value $content
        
        # Ensure .gitignore has the file
        $gitignore = Join-Path $OutputPath ".gitignore"
        if (Test-Path $gitignore) {
            $gitContent = Get-Content $gitignore -Raw
            if ($gitContent -notmatch '\.env\.secrets') {
                Add-Content -Path $gitignore -Value "`n.env.secrets"
            }
        }
    }
    
    return $envFile
}

function Save-ToGitHubSecrets {
    param([array]$Secrets)
    
    Write-Section "GITHUB SECRETS STORAGE" "Magenta"
    
    # Check GitHub CLI
    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        Write-Warn "GitHub CLI (gh) not installed."
        Write-Nfo "Install from: https://cli.github.com/"
        Write-Host ""
        $installNow = Read-Host "  Would you like to open the download page? (y/N)"
        if ($installNow -eq "y" -or $installNow -eq "Y") {
            Start-Process "https://cli.github.com/"
        }
        return $false
    }
    
    Write-OK "GitHub CLI detected"
    
    # Check auth
    $null = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Warn "GitHub CLI not authenticated."
        Write-Host ""
        $authNow = Read-Host "  Would you like to authenticate now? (y/N)"
        
        if ($authNow -eq "y" -or $authNow -eq "Y") {
            Write-Host ""
            Write-Step "Starting GitHub authentication..."
            Write-Host ""
            gh auth login
            
            # Re-check auth status
            $null = gh auth status 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Err "Authentication failed or cancelled."
                return $false
            }
            Write-OK "Successfully authenticated with GitHub!"
        }
        else {
            Write-Nfo "Skipped - Run 'gh auth login' manually when ready."
            return $false
        }
    }
    
    Write-OK "GitHub CLI authenticated"
    Write-Host ""
    Write-Host "  Secrets to store:" -ForegroundColor White
    
    foreach ($secret in $Secrets) {
        Write-Host "    * $($secret.Name): " -NoNewline -ForegroundColor Cyan
        Write-Host (Get-MaskedValue $secret.Value) -ForegroundColor Gray
    }
    
    Write-Host ""
    $confirm = Read-Host "  Store these in GitHub repository secrets? (y/N)"
    
    if ($confirm -ne "y" -and $confirm -ne "Y") {
        Write-Nfo "Skipped GitHub secrets storage."
        return $false
    }
    
    Write-Host ""
    
    if ($DryRun) {
        Write-Warn "DRY RUN - Would store $($Secrets.Count) secrets to GitHub"
        return $true
    }
    
    foreach ($secret in $Secrets) {
        Write-Step "Setting $($secret.Name)..."
        $secret.Value | gh secret set $secret.Name 2>&1 | Out-Null
        
        if ($LASTEXITCODE -eq 0) {
            Write-OK "$($secret.Name) stored successfully"
        }
        else {
            Write-Err "Failed to store $($secret.Name)"
        }
    }
    
    return $true
}

# ══════════════════════════════════════════════════════════════════════════════
# ADDITIONAL SECRETS FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

function Add-CustomSecrets {
    Write-Section "ADD CUSTOM SECRETS" "Blue"
    
    Write-Host "  Enter additional secrets (one per line, format: NAME=VALUE)" -ForegroundColor White
    Write-Host "  Press Enter on empty line when done." -ForegroundColor Gray
    Write-Host ""
    
    $customSecrets = @()
    $secretNamePattern = [regex]::new('^\s*(\w+)\s*=\s*(.+)\s*$')
    
    while ($true) {
        $userInput = Read-Host "  "
        
        if ([string]::IsNullOrWhiteSpace($userInput)) {
            break
        }
        
        $match = $secretNamePattern.Match($userInput)
        if ($match.Success) {
            $name = $match.Groups[1].Value.ToUpper()
            $value = $match.Groups[2].Value
            
            $customSecrets += @{
                Name = $name
                Value = $value
                Type = "Custom"
            }
            
            Write-OK "Added: $name = $(Get-MaskedValue $value)"
        }
        else {
            Write-Warn "Invalid format. Use: NAME=VALUE"
        }
    }
    
    return $customSecrets
}

# ══════════════════════════════════════════════════════════════════════════════
# MAIN EXECUTION
# ══════════════════════════════════════════════════════════════════════════════

function Main {
    Clear-Host
    Write-Banner
    
    if ($DryRun) {
        Write-Warn "DRY RUN MODE - No changes will be made"
        Write-Host ""
    }
    
    # Prompt for repository path
    Write-Host "  Enter the path to the repository you want to scan:" -ForegroundColor Cyan
    Write-Host ""
    $script:Path = Read-Host "  Path"
    
    # Handle empty input - use current directory
    if ([string]::IsNullOrWhiteSpace($script:Path)) {
        $script:Path = (Get-Location).Path
        Write-Host "  Using current directory: $script:Path" -ForegroundColor Gray
    }
    
    # Expand relative paths
    $script:Path = (Resolve-Path -Path $script:Path -ErrorAction SilentlyContinue).Path
    
    # Validate path
    if (-not $script:Path -or -not (Test-Path $script:Path)) {
        Write-Err "Path not found: $script:Path"
        exit 1
    }
    
    Write-Host ""
    
    # Scan codebase
    $secrets = Start-CodebaseScan -RootPath $Path
    
    # Show report
    Show-SecretsReport -Secrets $secrets
    
    # Sanitization
    $secretsToStore = Start-Sanitization -Secrets $secrets
    
    # Add custom secrets
    Write-Host ""
    $addMore = Read-Host "  Would you like to add additional secrets? (y/N)"
    
    if ($addMore -eq "y" -or $addMore -eq "Y") {
        $customSecrets = Add-CustomSecrets
        $secretsToStore += $customSecrets
    }
    
    if ($secretsToStore.Count -gt 0) {
        # Save to .env file
        Write-Host ""
        $envFile = Save-ToEnvFile -Secrets $secretsToStore -OutputPath $Path
        Write-OK "Secrets exported to: $envFile"
        
        # GitHub Secrets
        Write-Host ""
        $storeGH = Read-Host "  Store secrets in GitHub? (y/N)"
        
        if ($storeGH -eq "y" -or $storeGH -eq "Y") {
            Save-ToGitHubSecrets -Secrets $secretsToStore
        }
    }
    
    # Summary
    Write-Section "SUMMARY" "Green"
    
    Write-Host "  Scan Results:" -ForegroundColor White
    Write-Host "     * Secrets detected: $($secrets.Count)" -ForegroundColor $(if ($secrets.Count -gt 0) { "Yellow" } else { "Green" })
    Write-Host "     * Secrets processed: $($secretsToStore.Count)" -ForegroundColor Cyan
    Write-Host ""
    
    if ($secretsToStore.Count -gt 0) {
        Write-Host "  Next Steps:" -ForegroundColor White
        Write-Host "     1. Verify .env.secrets file is in .gitignore" -ForegroundColor Gray
        Write-Host "     2. Update application to read from environment variables" -ForegroundColor Gray
        Write-Host "     3. Test the application with new configuration" -ForegroundColor Gray
        Write-Host "     4. Commit sanitized files (without secrets)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "  " -NoNewline
    Write-Host "HADES" -ForegroundColor Cyan -NoNewline
    Write-Host " scan complete." -ForegroundColor Green
    Write-Host ""
}

# Run
Main
