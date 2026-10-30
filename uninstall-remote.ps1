# ============================================================================
#  uninstall-remote.ps1 - Claude Code supplier switcher (ccs) remote uninstall
#
#  Run with a single command (jsDelivr CDN, reachable from mainland China):
#      irm https://cdn.jsdelivr.net/gh/ldtmore/ClaudeCliSupplierSwitch@main/uninstall-remote.ps1 | iex
#
#  WHY THIS FILE EXISTS (and why it is ASCII-only, no BOM):
#  This file is executed via `irm | iex`. A UTF-8 BOM would glue an invisible
#  U+FEFF onto the first token and break iex parsing (phantom command errors).
#  Every byte here is ASCII so the script is independent of HTTP charset and
#  console codepage. All user-facing Chinese output lives in uninstall.ps1,
#  which is fetched and run below (irm decodes it via the HTTP charset).
# ============================================================================

$ErrorActionPreference = 'Stop'

# PS 5.1 needs TLS 1.2 enabled explicitly for HTTPS
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# Candidate sources: jsDelivr CDN first (reachable from mainland China, serves the
# exact repository content), GitHub raw as fallback
$urls = @(
    'https://cdn.jsdelivr.net/gh/ldtmore/ClaudeCliSupplierSwitch@main/uninstall.ps1',
    'https://raw.githubusercontent.com/ldtmore/ClaudeCliSupplierSwitch/main/uninstall.ps1'
)

$code = $null
foreach ($u in $urls) {
    Write-Host ('  -> Downloading: ' + $u)
    try { $code = Invoke-RestMethod -Uri $u -TimeoutSec 30; break } catch {
        Write-Host ('  [WARN] Unavailable: ' + $u) -ForegroundColor Yellow
    }
}
if (-not $code) {
    Write-Host '  X All download sources failed. Check your network, or clone the repo and run uninstall.ps1 locally.' -ForegroundColor Red
    # return instead of exit: under `irm | iex` an exit would close the user's shell session
    return
}

# Strip a UTF-8 BOM character if present, then execute the uninstaller in this session.
# Note: remote uninstall always keeps suppliers.json (the -Purge switch needs a local run).
iex (($code -replace '^\uFEFF', ''))
