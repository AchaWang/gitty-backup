<#
.SYNOPSIS
    Rclone Rule Manager - 智能掃描 Git Repo 並生成 Rclone 過濾規則腳本
.DESCRIPTION
    本腳本具備以下功能：
    1. ScanAndGenerate: 遞迴搜尋指定目錄下所有的 Git Repo，收集所有 .gitignore (包含子資料夾) 並生成 rclone_backup_rules.txt
    2. ListRepos: 快速掃描並列出所有偵測到的 Git 專案目錄
    3. DryRun: 使用生成的過濾規則進行 Rclone 模擬測試 (--dry-run)
    4. DumpFilters: 輸出 Rclone 內部解析後的過濾規則分析 (--dump filters)
    5. Backup: 實際執行 Rclone 備份程序
#>

param (
    [Parameter(Mandatory=$false)]
    [ValidateSet("ScanAndGenerate", "ListRepos", "DryRun", "DumpFilters", "Backup")]
    [string]$Action = "ScanAndGenerate",

    [Parameter(Mandatory=$false)]
    [string]$TargetDir = (Get-Item .).FullName,

    [Parameter(Mandatory=$false)]
    [string]$RemotePath = "backup_drive:TargetFolder",

    [Parameter(Mandatory=$false)]
    [string]$RulesFile = "",

    [Parameter(Mandatory=$false)]
    [ValidateSet("Copy", "Sync", "SyncArchive")]
    [string]$SyncMode = "Copy",

    [Parameter(Mandatory=$false)]
    [switch]$IncludeGitHistory = $true
)

# 強制設定 PowerShell 與 Windows 控制台的輸入/輸出編碼為 UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::InputEncoding = [System.Text.Encoding]::UTF8

# 確保路徑正則化為絕對路徑
$TargetDir = (Resolve-Path $TargetDir).Path

if ([string]::IsNullOrWhiteSpace($RulesFile)) {
    $RulesFile = Join-Path $TargetDir "rclone_backup_rules.txt"
} else {
    $RulesFile = [System.IO.Path]::GetFullPath($RulesFile)
}
$SummaryFile = Join-Path (Split-Path $RulesFile -Parent) "rclone_backup_summary.txt"

function Write-Log {
    param([string]$Message, [string]$Color = "White")
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor $Color
}

# ==========================================
# 1. 掃描 Git Repos
# ==========================================
function Get-GitRepositories {
    param([string]$Root)
    Write-Log "正在掃描目錄下所有 Git 專案: $Root ..." "Cyan"
    $GitDirs = Get-ChildItem -Path $Root -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq ".git" -and $_.PSIsContainer -and $_.FullName -notmatch "\\(node_modules|\.venv|\.cache)\\" }
    $Repos = @()
    foreach ($G in $GitDirs) {
        $RepoPath = $G.Parent.FullName
        $RelPath = $RepoPath.Replace($Root, "").TrimStart('\', '/')
        $Repos += [PSCustomObject]@{
            FullPath = $RepoPath
            RelativePath = if ($RelPath) { $RelPath.Replace('\', '/') } else { "[根目錄]" }
        }
    }
    return $Repos
}

# ==========================================
# 動作執行分流
# ==========================================
switch ($Action) {
    "ListRepos" {
        $Repos = Get-GitRepositories -Root $TargetDir
        Write-Log "==========================================" "Green"
        Write-Log " 📁 偵測到的 Git 專案清單 (共 $($Repos.Count) 個)" "Green"
        Write-Log "==========================================" "Green"
        foreach ($Repo in $Repos) {
            Write-Host " 📦 $($Repo.RelativePath)" -ForegroundColor Yellow
            Write-Host "    └─ Path: $($Repo.FullPath)`n" -ForegroundColor DarkGray
        }
    }

    "ScanAndGenerate" {
        $Repos = Get-GitRepositories -Root $TargetDir
        $Summary = @()
        $Rules = @()

        $Summary += "=========================================="
        $Summary += " 📁 Rclone 智能備份過濾規則報告"
        $Summary += "=========================================="
        $Summary += "掃描根目錄: $TargetDir"
        $Summary += "過濾表輸出: $RulesFile"
        $Summary += "產出時間: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        $Summary += "偵測到 Git 專案數: $($Repos.Count)"
        $Summary += "------------------------------------------`n"

        # --- 全域系統排除 (使用單引號防止 $RECYCLE 被 PowerShell 解析) ---
        $Rules += '# =========================================='
        $Rules += '# 1. 全域系統與暫存排除規則 (Global Excludes)'
        $Rules += '# =========================================='
        $Rules += '- **/.DS_Store'
        $Rules += '- **/Thumbs.db'
        $Rules += '- **/desktop.ini'
        $Rules += '- **/$RECYCLE.BIN/**'
        $Rules += '- **/System Volume Information/**'
        $Rules += '- **/*.tmp'
        $Rules += '- **/*.log'
        $Rules += ''

        # --- 是否排除 .git 歷史目錄 ---
        $Rules += "# =========================================="
        $Rules += "# 2. Git 歷史目錄設定"
        $Rules += "# =========================================="
        if (-not $IncludeGitHistory) {
            $Rules += "- **/.git/**"
            $Summary += "⚙️ Git 歷史紀錄: [排除] (- **/.git/**)"
        } else {
            $Summary += "⚙️ Git 歷史紀錄: [保留] (未排除 .git/ 目錄)"
        }
        $Rules += ""

        # --- 處理每個 Git Repo 的 .gitignore ---
        $Rules += "# =========================================="
        $Rules += "# 3. Git 專案 .gitignore 轉換規則 (經過優先權重與層級排序)"
        $Rules += "# =========================================="

        # 先收集整個工作區所有 .gitignore 下的「(+) 例外保留規則」，統一置於頂部
        # 為什麼？因為在 Rclone (--filter-from) 中，是由上到下「先搶先贏 (First Match Wins)」。
        # 若子目錄有 !important.json 保留，必須在任何上層或同層的 - *.json 排除命中前優先生效！
        $AllIncludeRules = @()
        $AllExcludeRulesByRepo = @()

        foreach ($Repo in $Repos) {
            $RepoRelPrefix = if ($Repo.RelativePath -eq "[根目錄]") { "" } else { $Repo.RelativePath }
            $Summary += "📦 Git Repo: $($Repo.RelativePath)"
            
            # 尋找該 Repo 下所有的 .gitignore (包含深層子目錄，但排除 .git 內部)
            # 依據目錄深度由深到淺排序，確保深層子資料夾的規則權重優於淺層
            $IgnoreFiles = Get-ChildItem -Path $Repo.FullPath -Filter ".gitignore" -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch "\\\.git\\" } | Sort-Object { ($_.FullName.Split('\')).Count } -Descending

            if ($IgnoreFiles.Count -eq 0) {
                $Summary += "   (無 .gitignore 檔案)`n"
                continue
            }

            $RepoExcludes = @()
            $RepoExcludes += "# Repo Excludes: $($Repo.RelativePath)"

            foreach ($IgnoreFile in $IgnoreFiles) {
                $SubRel = (Split-Path $IgnoreFile.FullName -Parent).Replace($TargetDir, "").TrimStart('\', '/').Replace('\', '/')
                $RulePrefix = if ($SubRel) { $SubRel } else { "" }
                
                $Summary += "   📄 讀取檔案: $($IgnoreFile.FullName.Replace($Repo.FullPath, '').TrimStart('\'))"

                Get-Content $IgnoreFile.FullName -Encoding UTF8 | ForEach-Object {
                    $Line = $_.Trim()
                    if ([string]::IsNullOrWhiteSpace($Line) -or $Line.StartsWith("#")) { return }

                    # 判斷保留(!)或排除(-)
                    $RuleAction = "-"
                    if ($Line.StartsWith("!")) {
                        $RuleAction = "+"
                        $Line = $Line.Substring(1).Trim()
                    }

                    # 移除開頭斜線來組裝
                    $LineBody = $Line.TrimStart('/')
                    $IsKnownDir = $Line.EndsWith("/") -or $LineBody -match "^(node_modules|\.venv|__pycache__|bin|obj|dist|build|env|venv|ENV|env\.bak|venv\.bak|uploads|images)$"
                    $CleanBody = $LineBody.TrimEnd('/')

                    $RulesToAdd = @()
                    if ($Line.StartsWith("/")) {
                        # 頂層指定規則
                        if ($IsKnownDir) {
                            $RulesToAdd += "$RuleAction $RulePrefix/$CleanBody/**"
                        } else {
                            $RulesToAdd += "$RuleAction $RulePrefix/$CleanBody"
                        }
                    } else {
                        # 非斜線開頭：Git 規範是「當層與所有深層子目錄皆適用」
                        # 因為 Rclone 中的 /**/ 必須匹配至少一層目錄，所以必須同時生成當層 ($RulePrefix/...) 與深層 ($RulePrefix/**/...)
                        if ($IsKnownDir) {
                            $RulesToAdd += "$RuleAction $RulePrefix/$CleanBody/**"
                            $RulesToAdd += "$RuleAction $RulePrefix/**/$CleanBody/**"
                        } else {
                            $RulesToAdd += "$RuleAction $RulePrefix/$CleanBody"
                            $RulesToAdd += "$RuleAction $RulePrefix/**/$CleanBody"
                        }
                    }

                    if ($RuleAction -eq "+") {
                        $AllIncludeRules += "# From: $($IgnoreFile.FullName.Replace($TargetDir, '').TrimStart('\'))"
                    }
                    foreach ($r in $RulesToAdd) {
                        $FinalRule = $r.Replace("//", "/")
                        if ($RuleAction -eq "+") {
                            $AllIncludeRules += $FinalRule
                        } else {
                            $RepoExcludes += $FinalRule
                        }
                    }
                    if ($RuleAction -eq "+") {
                        $Summary += "     🟢 (強制保留) -> $Line"
                    } else {
                        $Summary += "     🔴 (過濾排除) -> $Line"
                    }
                }
            }
            $AllExcludeRulesByRepo += $RepoExcludes
            $AllExcludeRulesByRepo += ""
            $Summary += ""
        }

        # 寫入保留例外與排除規則
        if ($AllIncludeRules.Count -gt 0) {
            $Rules += "# --- 3.1 跨專案所有強迫保留規則 (最高權重，防止先被頂層排除) ---"
            $Rules += $AllIncludeRules
            $Rules += ""
        }

        $Rules += "# --- 3.2 各專案排除規則 ---"
        $Rules += $AllExcludeRulesByRepo

        # --- 尾端預設保留 ---
        $Rules += "# =========================================="
        $Rules += "# 4. 預設保留其餘所有檔案"
        $Rules += "# =========================================="
        $Rules += "+ *"

        # 絕對不帶 BOM (\ufeff) 寫入 rules 檔案，防止 rclone 解析錯誤
        $RulesFileParent = Split-Path $RulesFile -Parent
        if (-not (Test-Path $RulesFileParent)) { New-Item -ItemType Directory -Force -Path $RulesFileParent | Out-Null }
        [System.IO.File]::WriteAllLines($RulesFile, $Rules, [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllLines($SummaryFile, $Summary, [System.Text.UTF8Encoding]::new($true))

        Write-Log "✅ 成功產出 Rclone 過濾規則表: $RulesFile" "Green"
        Write-Log "✅ 成功產出人類可讀統整報告: $SummaryFile" "Green"
        Write-Log "你可以使用 -Action DryRun 進行模擬測試！" "Yellow"
    }

    "DryRun" {
        if (-not (Test-Path $RulesFile)) {
            Write-Log "錯誤: 找不到 $RulesFile！請先執行 -Action ScanAndGenerate 產出規則。" "Red"
            return
        }
        $DryRunLog = Join-Path $TargetDir "rclone_dryrun.log"
        $SubCmd = "copy"
        $ExtraArgs = @()
        if ($SyncMode -eq "Sync") {
            $SubCmd = "sync"
            $ExtraArgs += "--delete-excluded"
            Write-Log "⚠️ 目前模式為 [嚴格鏡像同步 (Sync)]：來源已刪除或新列入過濾 exclusions 的檔案，目的端也將被刪除！" "Red"
        } elseif ($SyncMode -eq "SyncArchive") {
            $SubCmd = "sync"
            $ArchiveStamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
            $BackupDir = if ($RemotePath -match '^[a-zA-Z]:\\') {
                Join-Path ($RemotePath.TrimEnd('\') + "_Archive") $ArchiveStamp
            } elseif ($RemotePath -match ':') {
                $RemotePath.TrimEnd('/') + "_Archive/" + $ArchiveStamp
            } else {
                Join-Path ($RemotePath.TrimEnd('\', '/') + "_Archive") $ArchiveStamp
            }
            $ExtraArgs += @("--backup-dir", $BackupDir, "--delete-excluded")
            Write-Log "🛡️ 目前模式為 [同步+安全封存 (SyncArchive)]：目的端要刪除或被排除的舊檔案會封存至 [$BackupDir]" "Yellow"
        } else {
            Write-Log "🟢 目前模式為 [安全增量備份 (Copy)]：只複製新增/修改的檔案，不會刪除目的端舊檔" "Green"
        }

        Write-Log "正在執行 Rclone ($SubCmd) Dry-Run 測試 (模擬傳輸至 $RemotePath)..." "Cyan"
        Write-Log "💡 為了保護 UI 與終端機不被幾十萬行檔案列表洗版當機，詳細比對清單將自動寫入: $DryRunLog" "Yellow"
        Write-Log "畫面將為你實時顯示傳輸進度與總結報告：" "Cyan"
        & rclone $SubCmd $TargetDir $RemotePath --filter-from $RulesFile --dry-run --progress --log-file $DryRunLog --log-level INFO @ExtraArgs
        Write-Log "`n✅ Dry-Run 測試完成！詳細各檔案排除與模擬傳輸狀況已記錄在: $DryRunLog" "Green"
    }

    "DumpFilters" {
        if (-not (Test-Path $RulesFile)) {
            Write-Log "錯誤: 找不到 $RulesFile！請先執行 -Action ScanAndGenerate 產出規則。" "Red"
            return
        }
        $DumpLog = Join-Path $TargetDir "rclone_dump_filters.log"
        Write-Log "正在執行 Dump 分析 Rclone 內部過濾規則樹狀結構..." "Cyan"
        Write-Log "💡 你的工作區可能包含數萬筆以上檔案，分析報告將分流儲存至: $DumpLog" "Yellow"
        rclone ls $TargetDir --filter-from $RulesFile --dump filters 2>&1 | Out-File -FilePath $DumpLog -Encoding UTF8
        Write-Log "✅ Dump 分析完畢！以下為過濾樹前 30 行預覽：" "Green"
        Get-Content $DumpLog -TotalCount 30 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }
        Write-Log "`n完整 $( (Get-Content $DumpLog | Measure-Object).Count ) 行的過濾比對樹狀報告，已儲存至: $DumpLog" "Cyan"
    }

    "Backup" {
        if (-not (Test-Path $RulesFile)) {
            Write-Log "錯誤: 找不到 $RulesFile！請先執行 -Action ScanAndGenerate 產出規則。" "Red"
            return
        }
        $SubCmd = "copy"
        $ExtraArgs = @()
        if ($SyncMode -eq "Sync") {
            $SubCmd = "sync"
            $ExtraArgs += "--delete-excluded"
            Write-Log "⚠️ 開始 [嚴格鏡像同步 (Sync)]：來源已刪除或新列入過濾 exclusions 的檔案，目的端也將被刪除！" "Red"
        } elseif ($SyncMode -eq "SyncArchive") {
            $SubCmd = "sync"
            $ArchiveStamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
            $BackupDir = if ($RemotePath -match '^[a-zA-Z]:\\') {
                Join-Path ($RemotePath.TrimEnd('\') + "_Archive") $ArchiveStamp
            } elseif ($RemotePath -match ':') {
                $RemotePath.TrimEnd('/') + "_Archive/" + $ArchiveStamp
            } else {
                Join-Path ($RemotePath.TrimEnd('\', '/') + "_Archive") $ArchiveStamp
            }
            $ExtraArgs += @("--backup-dir", $BackupDir, "--delete-excluded")
            Write-Log "🛡️ 開始 [同步+安全封存 (SyncArchive)]：被刪除/修改/排除的舊檔案將封存至 [$BackupDir]" "Yellow"
        } else {
            Write-Log "🟢 開始 [安全增量備份 (Copy)]：只新增/更動，不刪除任何目的端舊資料..." "Green"
        }

        Write-Log "🚀 正在執行 rclone $SubCmd ..." "Green"
        & rclone $SubCmd $TargetDir $RemotePath --filter-from $RulesFile --progress @ExtraArgs
    }
}
