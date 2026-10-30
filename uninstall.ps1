# ============================================================================
#  uninstall.ps1 - Claude Code 多供应商切换工具（ccs）卸载
#  适用: Windows 10/11 · PowerShell 5.1 / PowerShell 7
#  用法: powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
#         加 -Purge 参数时连 suppliers.json（含 API Key）和上次使用记录一并删除
#  安全: 修改任何文件前自动生成 .bak-时间戳 备份；suppliers.json 默认保留
# ============================================================================
param([switch]$Purge)

$ErrorActionPreference = 'Stop'
$claudeDir = Join-Path $HOME '.claude'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'

function Write-Ok   { param([string]$Msg) Write-Host ('  [OK] ' + $Msg) -ForegroundColor Green }
function Write-Skip { param([string]$Msg) Write-Host ('  [跳过] ' + $Msg) -ForegroundColor DarkGray }
function Write-Warn2 { param([string]$Msg) Write-Host ('  [警告] ' + $Msg) -ForegroundColor Yellow }

Write-Host ''
Write-Host '===== Claude Code 多供应商切换工具（ccs）卸载 =====' -ForegroundColor Cyan
Write-Host ''

# ---------- 从 Profile 中移除挂载块 ----------
# 挂载块固定追加在文件末尾（PS 2 行 / bash 4 行）。仅当标记出现在最后 6 行内才自动移除，
# 否则说明文件结构有变，提示手动处理，避免误删其他内容。
function Remove-MenuMount {
    param([string]$Path, [string[]]$Marker, [switch]$IsBash)
    if (-not (Test-Path $Path)) { Write-Skip ($Path + ' 不存在'); return }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    # 读写编码跟随文件自身 BOM；无 BOM 时用 Latin-1（1 字节=1 字符）做无损往返：
    # ASCII 挂载标记在任何编码下都能匹配，未改动行按原字节写回，GBK/UTF-8 内容都不会被转码损坏
    $skip = 0
    $enc = [System.Text.Encoding]::GetEncoding(28591)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $enc = New-Object System.Text.UTF8Encoding($true); $skip = 3      # 重写时保留 BOM
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $enc = [System.Text.Encoding]::Unicode; $skip = 2
    } elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $enc = [System.Text.Encoding]::BigEndianUnicode; $skip = 2
    }
    $lines = $enc.GetString($bytes, $skip, $bytes.Length - $skip) -split "`n"
    $idx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($m in $Marker) {
            if ($lines[$i] -match [regex]::Escape($m)) { $idx = $i; break }
        }
        if ($idx -ge 0) { break }
    }
    if ($idx -lt 0) { Write-Skip ($Path + ' 未挂载'); return }
    if ($idx -lt $lines.Count - 6) {
        Write-Warn2 ($Path + ' 的挂载块不在文件末尾，为安全起见未自动移除，请手动删除标记行及其后的挂载块')
        return
    }
    Copy-Item -Path $Path -Destination ($Path + '.bak-' + $stamp)
    $keep = @()
    if ($idx -gt 0) { $keep = @($lines[0..($idx - 1)]) }
    # 去掉按 \n 切分后残留的行尾 \r，再按目标换行符重写：
    # .bashrc 必须保持 LF（CRLF 会导致 bash 把 \r 当命令的一部分），其余统一 CRLF
    $keep = @($keep | ForEach-Object { $_ -replace "`r$", '' })
    # 去掉切分产生的末尾空元素，文件末尾规范为单个换行（与旧版 ReadAllLines 行为一致，
    # 否则卸载后会在文件末尾多出一个空行）
    while ($keep.Count -gt 0 -and $keep[-1] -eq '') {
        if ($keep.Count -eq 1) { $keep = @() } else { $keep = @($keep[0..($keep.Count - 2)]) }
    }
    if ($IsBash) {
        [System.IO.File]::WriteAllText($Path, (($keep -join "`n") + "`n"), $enc)
    } else {
        [System.IO.File]::WriteAllLines($Path, $keep, $enc)
    }
    Write-Ok ('已移除挂载块（备份为 ' + [System.IO.Path]::GetFileName($Path) + '.bak-' + $stamp + '）')
}

$doc = [Environment]::GetFolderPath('MyDocuments')
# 新旧两种标记都识别：新版挂载块注释为 ASCII，v1.4.2 之前为中文注释
$ccsMarkers = @('Claude Code supplier menu', 'Claude Code 供应商菜单')
Remove-MenuMount -Path (Join-Path $doc 'PowerShell\Microsoft.PowerShell_profile.ps1') -Marker $ccsMarkers
Remove-MenuMount -Path (Join-Path $doc 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1') -Marker $ccsMarkers
Remove-MenuMount -Path (Join-Path $HOME '.bashrc') -Marker $ccsMarkers -IsBash

# ---------- 删除菜单脚本 ----------
foreach ($f in @('claude-menu.ps1', 'claude-menu.sh', 'suppliers.help.md')) {
    $p = Join-Path $claudeDir $f
    if (Test-Path $p) { Remove-Item $p -Force; Write-Ok ('已删除 ' + $p) }
}

# ---------- 供应商配置（默认保留） ----------
if ($Purge) {
    foreach ($f in @('suppliers.json', '.supplier-last')) {
        $p = Join-Path $claudeDir $f
        if (Test-Path $p) {
            Copy-Item -Path $p -Destination ($p + '.bak-' + $stamp)
            Remove-Item $p -Force
            Write-Ok ('已删除 ' + $f + '（备份为同目录 .bak-' + $stamp + '）')
        }
    }
} else {
    $supJson = Join-Path $claudeDir 'suppliers.json'
    if (Test-Path $supJson) {
        Write-Skip 'suppliers.json 已保留（含你的 API Key；如需一并删除请加 -Purge 参数重跑）'
    }
}

Write-Host ''
Write-Host '卸载完成。已开着的终端标签页不受影响，新开的标签页将不再有 ccs 命令。' -ForegroundColor DarkGray
Write-Host 'Claude Code 本体未被改动；如需彻底卸载请运行: npm uninstall -g @anthropic-ai/claude-code' -ForegroundColor DarkGray
Write-Host ''
