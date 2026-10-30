# ============================================================================
#  install-remote.ps1 - Claude Code 多供应商切换工具（ccs）远程一键部署
#  适用: Windows 10/11 · PowerShell 5.1 / PowerShell 7
#  执行契约: 本文件必须经 irm|iex 远程执行（字节按 HTTP charset=utf-8 解码后再解析，
#            无 BOM 也安全）；不可本地 -File 运行——无 BOM 中文会被 PS5.1 按 ANSI 误读
#            而报语法错。本地安装请用带 BOM 的 install.ps1。
#
#  用户只需在 PowerShell 执行一句（默认走 jsDelivr CDN，大陆直连可用）:
#      irm https://cdn.jsdelivr.net/gh/ldtmore/ClaudeCliSupplierSwitch@main/install-remote.ps1 | iex
#
#  能直连 GitHub 的用户可用官方源（与 CDN 源内容相同、互为回退）:
#      irm https://raw.githubusercontent.com/ldtmore/ClaudeCliSupplierSwitch/main/install-remote.ps1 | iex
#
#  原理: 从仓库下载全部文件到临时目录 → 以脚本块方式执行 install.ps1
#  （绕过本地执行策略限制）→ 幂等部署，与本地安装完全等效
# ============================================================================
param(
    # 仓库文件基地址（默认 jsDelivr CDN，大陆直连可用；fork 后可指向自己的仓库）
    [string]$Base = 'https://cdn.jsdelivr.net/gh/ldtmore/ClaudeCliSupplierSwitch@main',
    [switch]$SkipBash
)

$ErrorActionPreference = 'Stop'

function Write-Ok   { param([string]$Msg) Write-Host ('  [OK] ' + $Msg) -ForegroundColor Green }
function Write-Step { param([string]$Msg) Write-Host ('  -> ' + $Msg) }
function Write-Warn2 { param([string]$Msg) Write-Host ('  [警告] ' + $Msg) -ForegroundColor Yellow }

Write-Host ''
Write-Host '===== Claude Code 多供应商切换工具（ccs）远程部署 =====' -ForegroundColor Cyan
Write-Host ''

# PS 5.1 需显式启用 TLS 1.2 才能访问 HTTPS
try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

# 候选源：jsDelivr CDN 与 GitHub raw 互为回退（CDN 大陆友好、raw 为官方源），
# 回退沿用 $Base 里的同一 ref（分支/tag），避免固定 @main 造成版本错位
$bases = @($Base)
if ($Base -match '^https://raw\.githubusercontent\.com/([^/]+)/([^/]+)/([^/]+)/?$') {
    $bases += ('https://cdn.jsdelivr.net/gh/' + $Matches[1] + '/' + $Matches[2] + '@' + $Matches[3])
}
elseif ($Base -match '^https://cdn\.jsdelivr\.net/gh/([^/]+)/([^/]+)@([^/]+)/?$') {
    $bases += ('https://raw.githubusercontent.com/' + $Matches[1] + '/' + $Matches[2] + '/' + $Matches[3])
}

$files = @('install.ps1', 'claude-menu.ps1', 'claude-menu.sh', 'suppliers.help.md', 'suppliers.template.json')
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('ccs-remote-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null

$okBase = $null
foreach ($b in $bases) {
    Write-Step ('尝试下载源: ' + $b)
    try {
        foreach ($f in $files) {
            Invoke-WebRequest -UseBasicParsing -Uri ($b + '/' + $f) -OutFile (Join-Path $tmp $f) -TimeoutSec 30
        }
        $okBase = $b
        break
    } catch {
        Remove-Item -Path (Join-Path $tmp '*') -Force -ErrorAction SilentlyContinue
        Write-Warn2 ('该源不可用: ' + $b)
        continue
    }
}

if (-not $okBase) {
    Write-Host ''
    Write-Host '  ✘ 所有下载源均不可用。请检查网络，或改用镜像地址执行：' -ForegroundColor Red
    Write-Host '    irm https://cdn.jsdelivr.net/gh/ldtmore/ClaudeCliSupplierSwitch@main/install-remote.ps1 | iex' -ForegroundColor Yellow
    Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue
    # return 而非 exit：irm | iex 场景下 exit 会直接关掉用户当前的 PowerShell 会话
    return
}
Write-Ok ('文件下载完成（源: ' + $okBase + '）')

# 校验下载的 install.ps1 存在（return 同上，且先清理临时目录）
$localInstall = Join-Path $tmp 'install.ps1'
if (-not (Test-Path $localInstall)) { Write-Host '  ✘ 下载内容不完整' -ForegroundColor Red; Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue; return }

# 以脚本块方式执行安装器：不受本地执行策略限制，且无需落盘运行脚本文件
# 显式按 UTF-8 解码：不依赖 Get-Content 的 BOM 嗅探，install.ps1 无论带不带 BOM 都能正确读取
$code = Get-Content -Path $localInstall -Raw -Encoding UTF8
$sb = [scriptblock]::Create($code)
if ($SkipBash) { & $sb -SrcDir $tmp -SkipBash } else { & $sb -SrcDir $tmp }

Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host '  远程卸载（日后需要时执行）: irm https://cdn.jsdelivr.net/gh/ldtmore/ClaudeCliSupplierSwitch@main/uninstall-remote.ps1 | iex' -ForegroundColor DarkGray
Write-Host ''
