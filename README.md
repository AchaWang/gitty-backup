# ⚡ Gitty-Backup —— 讓備份，像 Git 一樣精確優雅

> **「整合式備份與同步工具 · 自動排除不需要的零碎檔案。秉持 Git 風格的精準哲學，只備份真正重要的核心資料！」**

![Platform](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?style=flat-square&logo=windows)
![Framework](https://img.shields.io/badge/.NET-10.0%20WPF-512BD4?style=flat-square&logo=dotnet)
![Engine](https://img.shields.io/badge/Engine-Rclone%20%2B%20PowerShell%205.1-4EAA25?style=flat-square)
![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)

---

## 💡 為什麼需要 Gitty-Backup？

對於軟體工程師與研究人員來說，我們的日常工作區（例如 `C:\Users\...\_Project`）通常包含了數十甚至數百個 Git 小專案與練習課業。  
當使用傳統備份工具（如直接複製、一般雲端同步軟體或基礎 Rclone 指令）進行全盤備份時，往往會面臨嚴重的 **「黑洞災難」**：

1. **肥大的第三方程式庫與快取**：數十萬個 `node_modules`、`.venv`、`.vs`、`bin`、`obj`、`__pycache__` 等資料夾被一併打包。
2. **傳輸極速下降與硬碟磨損**：幾百 KB 的真正原始碼，卻伴隨著幾十 GiB 的小碎檔案傳輸，備份一次耗時數個小時。
3. **金庫雜亂無章**：目的地硬碟塞滿了隨時可重新 `npm install` 或編譯生成的垃圾暫存。

**Gitty-Backup** 正是為了解決這個痛點而生！它採用了 **`Git-aware` (Git 感知)** 哲學，將你的專案結構與 `.gitignore` 視為單一真理來源，自動把各專案的忽略規則編譯轉換為 Rclone 專屬的樹狀過濾表，讓你體驗最純淨、最高速的極致備份！

---

## 🌟 核心亮點功能

### 🧠 1. 智能 Git `.gitignore` 樹狀過濾引擎
* **自動遞迴掃描**：一鍵掃描目標根目錄下所有的 Git 儲存庫 (`Repo`)，精準識別深層子目錄中的所有 `.gitignore` 檔案。
* **權重與優先順序校正**：自動依據目錄深度由深至淺排序，確保子資料夾的過濾與例外規則優先於上層。
* **語法高階轉換**：支援 `.gitignore` 中的 `!` 強制保留例外語法（自動置頂轉換為 Rclone `+` 規則），並正確將 Git 當層/所有深層通配符轉換為 Rclone 雙層過濾 (`/**/`)。

### 🛡️ 2. 全局常見開發黑洞雙重防禦 (`Global Dev Blackhole Shield`)
* 即使是**尚未建立 Git 儲存庫 (`git init`)** 的臨時練習或學校課業資料夾，系統也自動在全域層級安全過濾以下開發黑洞：
  * **IDE 快取**：`.vs/`、`.idea/`、`.vscode/`、`*.suo`、`*.user`、`*.vsidx`
  * **編譯暫存與套件**：`node_modules/`、`.venv/`、`venv/`、`env/`、`__pycache__/`、`bin/`、`obj/`、`dist/`、`build/`
  * **系統垃圾**：`.DS_Store`、`Thumbs.db`、`desktop.ini`、`$RECYCLE.BIN`、`*.tmp`、`*.log`

### 💻 3. 現代化 WPF 視覺化控制中心
* **實時滾動雙向日誌 (`Live Log View`)**：採用背景獨立執行緒 (`Task`) 搭配 `DispatcherTimer` 100ms 批次緩衝輸出技術，即使 Rclone 瞬間吐出幾十萬筆檔案清單，UI 也平滑流暢、**絕對不會當機卡死**！
* **一鍵模擬與結構分析**：內建 **Dry-Run 模擬測試** 與 **Dump Filters 樹狀結構分析**，正式備份前即可精準預覽每一個檔案的命中狀態。
* **雙向嚴格完整性校驗 (`Check`)**：一鍵啟動 Rclone `check` 引擎，嚴格驗證目的地硬碟與過濾後的來源目錄是否 100% 毫秒級吻合，做到真正的安心備份。

### 🛡️ 4. 三大智慧安全備份模式

| 模式名稱 | 運作原理 (`Rclone Engine`) | 適用場景與特色 |
| :--- | :--- | :--- |
| **🟢 安全增量備份 (`Copy`)** | `rclone copy` | **最保守安全**！只複製新增與有修改的檔案，目的地硬碟中任何既有的舊檔案皆**不會被刪除**。 |
| **⚠️ 嚴格鏡像同步 (`Sync`)** | `rclone sync --delete-excluded` | **極致純淨鏡像**！使目的地與來源端 100% 一模一樣。如果來源端刪除了檔案，或你新加入了 `.gitignore` 排除規則，目的地的舊檔也會被同步清除。 |
| **🛡️ 同步 + 安全封存 (`SyncArchive`)**<br>*(🔥強烈推薦！)* | `rclone sync --delete-excluded --backup-dir <ArchiveDir>` | **零資料遺失風險的時光機！** 達成純淨鏡像同步的同時，把目的地即將被刪除或覆寫的舊檔案，自動遷移並按日期封存至 `_Archive/yyyy-MM-dd_HHmmss/` 資料夾中！ |

---

## 🏛️ 專案架構與目錄結構

本專案採用極致潔癖的目錄收斂設計，C# 主程式與 PowerShell 核心過濾引擎緊密協作，且腳本絕不散落：

```text
Gitty-Backup/
│
├── README.md                          <-- 本專案說明文件
├── .gitignore                         <-- Git 忽略設定
│
├── GittyBackup/                       <-- WPF / C# 桌面控制中心核心原始碼
│   ├── GittyBackup.csproj             <-- .NET 10.0 WPF 專案設定檔
│   ├── App.xaml / App.xaml.cs         <-- 應用程式進入點與資源
│   ├── MainWindow.xaml / .cs          <-- 視覺化介面與背景任務控制器
│   ├── AssemblyInfo.cs
│   │
│   └── Scripts/                       <-- 🔥 全專案唯一的 PowerShell 控制腳本庫
│       └── RcloneRuleManager.ps1      <-- MSBuild 於建置時自動同步至發布輸出目錄
│
└── Standalone_Release/                <-- 🚀 免安裝獨立正式發布金庫 (Portable)
    ├── GittyBackup.exe                <-- 獨立單檔執行檔 (自帶 .NET 10 & WPF 引擎)
    └── Scripts/
        └── RcloneRuleManager.ps1      <-- 自動精準對齊的過濾引擎
```

---

## 🚀 快速上手與操作教學

### 🛠️ 系統需求
* **作業系統**：Windows 10 / Windows 11 (x64)
* **後端引擎**：系統環境參數 (`PATH`) 中需已安裝並可直接調用 `rclone` (PowerShell 預設已具備 PS 5.1)。
* **執行方式**：直接雙擊 `Standalone_Release\GittyBackup.exe` 即可免安裝秒開即用！

### 📋 標準操作六部曲

1. **設定路徑**：
   * **掃描目標根目錄 (`TargetDir`)**：選擇你要備份的專案總目錄（例如 `C:\Users\Acha\Desktop\Acha`）。
   * **目的地 / 遠端路徑 (`RemotePath`)**：輸入外接硬碟路徑或雲端金庫名稱（例如 `E:\_Acha` 或 `gdrive:MyBackup`）。
2. **Step 1. 列出 Git 專案 (`ListRepos`)**：點擊按鈕，系統會快速掃描並在畫面上列出所有偵測到的 Git 儲存庫。
3. **Step 2. 產出過濾表 (`ScanAndGenerate`)**：點擊按鈕，系統將智能收集所有的 `.gitignore` 與全局排除黑洞，瞬間在根目錄下生成 `rclone_backup_rules.txt` 與人類可讀摘要報告。
4. **Step 3. 模擬測試 (`Dry-Run` - 強烈建議！)**：在實際傳輸前點擊模擬測試，畫面與日誌將清楚列出哪幾萬個檔案被排除、哪幾個真實檔案將被傳輸。
5. **Step 5. 立即備份 (`Backup`)**：確認無誤後，選擇你偏好的模式（建議選 **🛡️ 同步 + 安全封存 SyncArchive**），點擊「立即備份」，監看實時高速進度列！
6. **Step 6. 完整性校驗 (`Check`)**：備份完成後，隨時點擊「6. 完整性校驗」，讓 Rclone 嚴格為你比對來源與目標金庫是否 100% 完美吻合。

---

## 💻 自行建置與編譯指令 (`Build & Publish`)

如果你想自行修改原始碼並重新編譯，可在終端機進入 `GittyBackup` 目錄後執行以下指令：

#### 🟢 方案 A：輕量框架相依版 (`Framework-Dependent` - 產出約 140 KB)
適合本機已有安裝 `.NET 10.0 Desktop Runtime` 的開發者：
```powershell
cd GittyBackup
dotnet build -c Release
```
產出目錄：`GittyBackup\bin\Release\net10.0-windows\`

#### 🚀 方案 B：隨身碟免安裝獨立單檔版 (`Self-Contained Portable` - 產出約 125 MB)
將完整的 `.NET 10 Runtime` 與 `WPF 引擎` 打包入單一執行檔，隨身碟帶走插上任何 Windows 皆可秒開：
```powershell
cd GittyBackup
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -o "..\Standalone_Release"
```
產出目錄：`Standalone_Release\`

---

## 👨‍💻 技術支持與開發哲學

**Gitty-Backup** 秉持著 *「自動化、透明化、潔癖化」* 的精神開發。  
如果在使用本工具或備份大型資料庫的過程中有任何功能建議或優化需求，歡迎隨時提交 Feedback 或 Issue！為你的數位資產提供最堅固的防護盾牌！ 🛡️🐕✨
