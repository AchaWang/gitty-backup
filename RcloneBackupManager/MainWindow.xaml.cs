using System;
using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Windows;
using System.Windows.Threading;
using Microsoft.Win32;

namespace RcloneBackupManager
{
    public partial class MainWindow : Window
    {
        private Process? _currentProcess = null;
        private readonly ConcurrentQueue<string> _logQueue = new ConcurrentQueue<string>();
        private readonly DispatcherTimer _logTimer;
        private const int MaxConsoleLines = 5000;

        public MainWindow()
        {
            // 1. 在建構子最上方註冊 CodePages (防亂碼極度重要處理)
            Encoding.RegisterProvider(CodePagesEncodingProvider.Instance);

            InitializeComponent();

            // 預設來源與目的地
            string desktopAcha = @"C:\Users\Acha\Desktop\Acha";
            TargetDirTextBox.Text = Directory.Exists(desktopAcha) ? desktopAcha : AppDomain.CurrentDomain.BaseDirectory;
            RemotePathTextBox.Text = @"D:\Backup\Acha";
            RulesPathTextBox.Text = Path.Combine(TargetDirTextBox.Text, "rclone_backup_rules.txt");

            // 初始化日誌緩衝計時器 (每 100 毫秒批次刷新 UI，防當機核心)
            _logTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromMilliseconds(100)
            };
            _logTimer.Tick += LogTimer_Tick;
            _logTimer.Start();
        }

        private void LogTimer_Tick(object? sender, EventArgs e)
        {
            if (_logQueue.IsEmpty) return;

            var sb = new StringBuilder();
            int count = 0;
            // 每次最多從佇列取出 500 行，避免單次 UI 更新負擔過重
            while (count < 500 && _logQueue.TryDequeue(out string? line))
            {
                sb.AppendLine(line);
                count++;
            }

            if (sb.Length > 0)
            {
                ConsoleTextBox.AppendText(sb.ToString());

                // 限制最大行數，防止 WPF 記憶體爆滿導致卡死與當機
                if (ConsoleTextBox.LineCount > MaxConsoleLines)
                {
                    string fullText = ConsoleTextBox.Text;
                    // 保留最後 4000 行
                    int linesToRemove = ConsoleTextBox.LineCount - 4000;
                    int cutIndex = 0;
                    for (int i = 0; i < linesToRemove && cutIndex < fullText.Length; i++)
                    {
                        cutIndex = fullText.IndexOf('\n', cutIndex) + 1;
                        if (cutIndex <= 0) break;
                    }
                    if (cutIndex > 0 && cutIndex < fullText.Length)
                    {
                        ConsoleTextBox.Text = "[...先前過多的日誌已自動省略以保護系統記憶體...]\r\n" + fullText.Substring(cutIndex);
                    }
                }

                ConsoleTextBox.ScrollToEnd();
            }
        }

        private void BrowseTargetDir_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFolderDialog
            {
                Title = "選擇要掃描與備份的來源目錄 (Target Folder)",
                InitialDirectory = TargetDirTextBox.Text
            };

            if (dialog.ShowDialog() == true)
            {
                TargetDirTextBox.Text = dialog.FolderName;
            }
        }

        private void BrowseRemoteDir_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFolderDialog
            {
                Title = "選擇硬碟備份目的地資料夾 (Remote/HDD Path)",
                InitialDirectory = Directory.Exists(RemotePathTextBox.Text) ? RemotePathTextBox.Text : TargetDirTextBox.Text
            };

            if (dialog.ShowDialog() == true)
            {
                RemotePathTextBox.Text = dialog.FolderName;
            }
        }

        private void BrowseRulesFile_Click(object sender, RoutedEventArgs e)
        {
            var dialog = new OpenFileDialog
            {
                Title = "選擇或指定 Rclone 過濾規則表檔案路徑 (Rules File)",
                Filter = "文字檔 (*.txt)|*.txt|所有檔案 (*.*)|*.*",
                FileName = "rclone_backup_rules.txt",
                CheckFileExists = false
            };

            if (dialog.ShowDialog() == true)
            {
                RulesPathTextBox.Text = dialog.FileName;
            }
        }

        private void SetExampleHDD_Click(object sender, RoutedEventArgs e)
        {
            RemotePathTextBox.Text = @"D:\Backup\Acha";
            AppendLog("已填入硬碟備份範例目的地: D:\\Backup\\Acha");
        }

        private void SetExampleGDrive_Click(object sender, RoutedEventArgs e)
        {
            RemotePathTextBox.Text = @"gdrive:Backup/Acha";
            AppendLog("已填入 Google Drive 遠端備份範例: gdrive:Backup/Acha");
        }

        private void BtnListRepos_Click(object sender, RoutedEventArgs e)
        {
            RunScriptAsync("ListRepos", "正在掃描目標目錄下的所有 Git 專案...");
        }

        private void BtnScanAndGenerate_Click(object sender, RoutedEventArgs e)
        {
            RunScriptAsync("ScanAndGenerate", "正在讀取各 Repo 的 .gitignore 並生成 rclone_backup_rules.txt...");
        }

        private void BtnDryRun_Click(object sender, RoutedEventArgs e)
        {
            RunScriptAsync("DryRun", "正在進行 Rclone 模擬測試 (Dry-Run)...");
        }

        private void BtnDumpFilters_Click(object sender, RoutedEventArgs e)
        {
            RunScriptAsync("DumpFilters", "正在 Dump 分析 Rclone 內部過濾樹狀結構...");
        }

        private void BtnBackup_Click(object sender, RoutedEventArgs e)
        {
            var result = MessageBox.Show(
                $"確定要開始執行 Rclone 備份至目的地嗎？\n\n來源：{TargetDirTextBox.Text}\n目的地：{RemotePathTextBox.Text}",
                "確認執行備份", MessageBoxButton.YesNo, MessageBoxImage.Question);

            if (result == MessageBoxResult.Yes)
            {
                RunScriptAsync("Backup", "🚀 正在執行 Rclone 備份至目的地...");
            }
        }

        private void BtnCheck_Click(object sender, RoutedEventArgs e)
        {
            RunScriptAsync("Check", "正在進行 Rclone 嚴格雙向完整性校驗...");
        }

        private void BtnStop_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                if (_currentProcess != null && !_currentProcess.HasExited)
                {
                    _currentProcess.Kill();
                    AppendLog("\n[⏹ 任務已被使用者強制終止]");
                    SetUiBusy(false);
                }
            }
            catch (Exception ex)
            {
                AppendLog($"\n[停止任務出錯: {ex.Message}]");
            }
        }

        private void BtnClearConsole_Click(object sender, RoutedEventArgs e)
        {
            ConsoleTextBox.Clear();
            while (_logQueue.TryDequeue(out _)) { }
        }

        private void RunScriptAsync(string action, string statusDescription)
        {
            if (_currentProcess != null && !_currentProcess.HasExited)
            {
                MessageBox.Show("目前已有指令正在執行中，請先等候其完成或點擊「停止目前任務」。", "忙碌中", MessageBoxButton.OK, MessageBoxImage.Warning);
                return;
            }

            string targetDir = TargetDirTextBox.Text.Trim();
            string remotePath = RemotePathTextBox.Text.Trim();
            string rulesPath = RulesPathTextBox.Text.Trim();
            bool includeGit = chkIncludeGitHistory.IsChecked == true;

            if (string.IsNullOrEmpty(targetDir))
            {
                MessageBox.Show("請先選擇或填寫來源目錄 (Target Folder)！", "提示", MessageBoxButton.OK, MessageBoxImage.Exclamation);
                return;
            }
            if (string.IsNullOrEmpty(rulesPath))
            {
                rulesPath = Path.Combine(targetDir, "rclone_backup_rules.txt");
            }

            // 尋找腳本路徑
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string scriptPath = Path.Combine(baseDir, "Scripts", "RcloneRuleManager.ps1");

            // 如果 bin 目錄下找不到，嘗試往上找開發目錄
            if (!File.Exists(scriptPath))
            {
                scriptPath = Path.GetFullPath(Path.Combine(baseDir, @"..\..\..\Scripts\RcloneRuleManager.ps1"));
            }

            if (!File.Exists(scriptPath))
            {
                // 嘗試找上層或移動後的 _Project/rclone-ui 目錄
                scriptPath = Path.GetFullPath(Path.Combine(baseDir, @"..\..\..\..\RcloneRuleManager.ps1"));
            }

            if (!File.Exists(scriptPath))
            {
                scriptPath = @"C:\Users\Acha\Desktop\Acha\_Project\rclone-ui\RcloneRuleManager.ps1";
            }
            if (!File.Exists(scriptPath))
            {
                scriptPath = @"C:\Users\Acha\Desktop\Acha\rclone-ui\RcloneRuleManager.ps1";
            }

            if (!File.Exists(scriptPath))
            {
                AppendLog($"[錯誤] 找不到腳本檔案: {scriptPath}");
                MessageBox.Show("找不到核心控制腳本 RcloneRuleManager.ps1！", "錯誤", MessageBoxButton.OK, MessageBoxImage.Error);
                return;
            }

            // 確保 PowerShell 腳本具有 UTF-8 BOM，防止 PowerShell 5.1 把中文註解讀成亂碼導致語法錯誤
            try
            {
                byte[] bytes = File.ReadAllBytes(scriptPath);
                if (bytes.Length >= 3 && !(bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF))
                {
                    byte[] bom = new byte[] { 0xEF, 0xBB, 0xBF };
                    byte[] newBytes = new byte[bom.Length + bytes.Length];
                    Buffer.BlockCopy(bom, 0, newBytes, 0, bom.Length);
                    Buffer.BlockCopy(bytes, 0, newBytes, bom.Length, bytes.Length);
                    File.WriteAllBytes(scriptPath, newBytes);
                }
            }
            catch { /* 忽略鎖定或唯讀錯誤 */ }

            string syncMode = "Copy";
            if (rbModeSyncArchive.IsChecked == true) syncMode = "SyncArchive";
            else if (rbModeSync.IsChecked == true) syncMode = "Sync";

            SetUiBusy(true, statusDescription);
            AppendLog($"\n=======================================================");
            AppendLog($"執行動作: [{action}]");
            AppendLog($"來源目錄: {targetDir}");
            AppendLog($"備份目的地: {remotePath}");
            AppendLog($"過濾規則表: {rulesPath}");
            AppendLog($"同步模式: [{syncMode}]");
            AppendLog($"保留 Git 歷史: {includeGit}");
            AppendLog($"=======================================================\n");

            string includeGitParam = includeGit ? "$true" : "$false";
            string psCommand = $"& '{scriptPath}' -Action {action} -TargetDir '{targetDir}' -RemotePath '{remotePath}' -RulesFile '{rulesPath}' -SyncMode '{syncMode}' -IncludeGitHistory:{includeGitParam}";

            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-ExecutionPolicy Bypass -NoProfile -Command \"{psCommand}\"",
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                CreateNoWindow = true,
                WorkingDirectory = Path.GetDirectoryName(scriptPath) ?? baseDir
            };

            // 2. 設定 ProcessStartInfo 的編碼為 UTF-8，與 PowerShell 的 UTF-8 控制台輸出完美對接，防止 Rclone 縮寫符號 (…) 被轉為 Big5 亂碼
            psi.StandardOutputEncoding = Encoding.UTF8;
            psi.StandardErrorEncoding = Encoding.UTF8;

            _currentProcess = new Process { StartInfo = psi, EnableRaisingEvents = true };

            _currentProcess.OutputDataReceived += (s, ev) =>
            {
                if (ev.Data != null) AppendLog(ev.Data);
            };

            _currentProcess.ErrorDataReceived += (s, ev) =>
            {
                if (ev.Data != null) AppendLog($"[ERROR] {ev.Data}");
            };

            _currentProcess.Exited += (s, ev) =>
            {
                Dispatcher.InvokeAsync(() =>
                {
                    // 確保佇列中剩餘的日誌在結束後被刷新
                    LogTimer_Tick(null, EventArgs.Empty);
                    SetUiBusy(false);
                    AppendLog($"\n[✔ 任務已結束]");
                });
            };

            try
            {
                _currentProcess.Start();
                _currentProcess.BeginOutputReadLine();
                _currentProcess.BeginErrorReadLine();
            }
            catch (Exception ex)
            {
                AppendLog($"[啟動失敗]: {ex.Message}");
                SetUiBusy(false);
            }
        }

        private void AppendLog(string message)
        {
            // 將訊息放進高並發安全佇列，不再直接阻塞 UI 執行緒
            _logQueue.Enqueue(message);
        }

        private void SetUiBusy(bool isBusy, string status = "")
        {
            btnStopProcess.IsEnabled = isBusy;
            txtTaskStatus.Text = isBusy ? " [執行中...]" : " [就緒]";
            txtTaskStatus.Foreground = isBusy ? new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(243, 139, 168)) : new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(166, 227, 161));
            if (!string.IsNullOrEmpty(status)) StatusBarText.Text = status;
        }
    }
}