/* ==========================================================================
   Gitty-Backup GitHub Pages Interactive Logic (Terminal Simulator & Mode Tabs)
   ========================================================================== */

document.addEventListener('DOMContentLoaded', () => {
  const terminalBody = document.getElementById('terminalBody');
  const termButtons = document.querySelectorAll('.term-btn');
  const modeTabs = document.querySelectorAll('.mode-tab');
  const modePanes = document.querySelectorAll('.mode-pane');
  const copyButtons = document.querySelectorAll('.copy-btn');

  // Simulated Logs for each Action
  const terminalLogs = {
    ListRepos: [
      { time: '23:58:01', color: 'log-cyan', text: '⚡ Gitty-Backup (Rclone Rule Manager) —— 開始執行 ListRepos 任務' },
      { time: '23:58:01', color: 'log-time', text: '正在遞迴搜尋目標目錄下的 Git 儲存庫：C:\\Users\\Acha\\Desktop\\Acha' },
      { time: '23:58:02', color: 'log-green', text: '[+ Git Repo] 偵測到 C:\\Users\\Acha\\Desktop\\Acha\\_Project\\gitty-backup (.git)' },
      { time: '23:58:02', color: 'log-green', text: '[+ Git Repo] 偵測到 C:\\Users\\Acha\\Desktop\\Acha\\_Project\\acha-kms-ui (.git)' },
      { time: '23:58:03', color: 'log-green', text: '[+ Git Repo] 偵測到 C:\\Users\\Acha\\Desktop\\Acha\\_Project\\achawang.github.io (.git)' },
      { time: '23:58:03', color: 'log-yellow', text: '掃描完成！共發現 14 個 Git 儲存庫。' }
    ],
    ScanAndGenerate: [
      { time: '23:58:10', color: 'log-cyan', text: '⚡ 啟動 ScanAndGenerate：掃描 Git Repo 並解析多層級 .gitignore...' },
      { time: '23:58:10', color: 'log-purple', text: '=> 載入 Section 1 & 1.5 全域通用開發黑洞規則 (.vs, bin, obj, node_modules, .venv)...' },
      { time: '23:58:11', color: 'log-time', text: '正在由深至淺依序轉換 28 張 .gitignore 規則樹...' },
      { time: '23:58:11', color: 'log-green', text: '[✔ 轉換成功] gitty-backup/.gitignore -> + Standalone_Release/GittyBackup.exe' },
      { time: '23:58:12', color: 'log-green', text: '[✔ 轉換成功] 深度樹狀例外保留語法 (!) 已精準轉換為 Rclone 加號規則 (+)' },
      { time: '23:58:12', color: 'log-cyan', text: '✔ 過濾規則表已完整產出：C:\\Users\\Acha\\Desktop\\Acha\\rclone_backup_rules.txt (1,482 行)' }
    ],
    DryRun: [
      { time: '23:58:20', color: 'log-yellow', text: '🔬 啟動 Rclone 模擬測試 (--dry-run) —— 零風險驗證過濾結果' },
      { time: '23:58:20', color: 'log-time', text: '執行指令: rclone sync C:\\Users\\Acha\\Desktop\\Acha E:\\_Acha --filter-from rclone_backup_rules.txt --dry-run -v' },
      { time: '23:58:21', color: 'log-purple', text: '2026/07/15 23:58:21 NOTICE: _Project/gitty-backup/bin/Release/... : Excluded from sync' },
      { time: '23:58:21', color: 'log-purple', text: '2026/07/15 23:58:21 NOTICE: _Class/nw_program/.vs/.../FileContentIndex/*.vsidx : Excluded by global rules' },
      { time: '23:58:22', color: 'log-green', text: '2026/07/15 23:58:22 NOTICE: _Project/gitty-backup/GittyBackup/MainWindow.xaml.cs : Not copying as --dry-run' },
      { time: '23:58:22', color: 'log-cyan', text: '📊 模擬測試結束！預計排除 23,261 個快取黑洞，傳輸 87 個真正原始碼檔案！' }
    ],
    SyncArchive: [
      { time: '23:58:30', color: 'log-red', text: '🚀 啟動 SyncArchive：純淨鏡像同步 + _Archive 自動時光機封存！' },
      { time: '23:58:30', color: 'log-time', text: '建立封存資料夾: E:\\_Acha\\_Archive\\2026-07-15_235830' },
      { time: '23:58:31', color: 'log-green', text: '2026/07/15 23:58:31 INFO : _Project/gitty-backup/Standalone_Release/GittyBackup.exe: Copied (new)' },
      { time: '23:58:32', color: 'log-yellow', text: '2026/07/15 23:58:32 INFO : old_test.log: Moved to _Archive/2026-07-15_235830/old_test.log (Backup)' },
      { time: '23:58:33', color: 'log-cyan', text: '🎉 備份大功告成！耗時 2.8 秒，所有舊檔安全遷移封存，目的地金庫 100% 鏡像純淨！' }
    ],
    Check: [
      { time: '23:58:40', color: 'log-cyan', text: '🛡️ 啟動 Check：Rclone 嚴格完整性與雜湊值校驗' },
      { time: '23:58:40', color: 'log-time', text: '比對來源：C:\\Users\\Acha\\Desktop\\Acha  <=>  目的地：E:\\_Acha' },
      { time: '23:58:41', color: 'log-green', text: '2026/07/15 23:58:41 INFO : 正在進行 SHA-1/MD5 雙向快速哈希比對...' },
      { time: '23:58:42', color: 'log-green', text: '2026/07/15 23:58:42 NOTICE: 0 differences found across 3,428 valid project files.' },
      { time: '23:58:42', color: 'log-cyan', text: '✔ 校驗成功！目的地硬碟金庫狀態 100% 完美吻合，毫無破損！' }
    ]
  };

  function playTerminalLogs(actionKey) {
    terminalBody.innerHTML = '';
    const logs = terminalLogs[actionKey] || terminalLogs['ScanAndGenerate'];
    let delay = 0;

    logs.forEach((item, idx) => {
      setTimeout(() => {
        const div = document.createElement('div');
        div.className = 'term-line';
        div.innerHTML = `<span class="log-time">[${item.time}]</span> <span class="${item.color}">${item.text}</span>`;
        terminalBody.appendChild(div);
        terminalBody.scrollTop = terminalBody.scrollHeight;
      }, delay);
      delay += 350;
    });
  }

  // Terminal Button Click Events
  termButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      termButtons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');
      const action = btn.getAttribute('data-action');
      playTerminalLogs(action);
    });
  });

  // Initial Play
  playTerminalLogs('ScanAndGenerate');

  // Mode Tabs Switching
  modeTabs.forEach(tab => {
    tab.addEventListener('click', () => {
      modeTabs.forEach(t => t.classList.remove('active'));
      modePanes.forEach(p => p.classList.remove('active'));
      
      tab.classList.add('active');
      const targetPane = document.getElementById(tab.getAttribute('data-tab'));
      if (targetPane) targetPane.classList.add('active');
    });
  });

  // Copy Buttons
  copyButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      const codeId = btn.getAttribute('data-copy');
      const codeEl = document.getElementById(codeId);
      if (codeEl) {
        navigator.clipboard.writeText(codeEl.innerText).then(() => {
          const originalText = btn.innerText;
          btn.innerText = '✔ Copied!';
          btn.style.background = '#a6e3a1';
          btn.style.color = '#11111b';
          setTimeout(() => {
            btn.innerText = originalText;
            btn.style.background = '';
            btn.style.color = '';
          }, 2000);
        });
      }
    });
  });
});
