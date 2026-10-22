/// App 內建的版本歷程（離線也看得到）。新增版本時，請同步更新 CHANGELOG.md。
class ChangelogEntry {
  const ChangelogEntry(this.version, this.zh, this.en);

  final String version;
  final List<String> zh;
  final List<String> en;
}

const List<ChangelogEntry> kChangelog = <ChangelogEntry>[
  ChangelogEntry(
    '2.3.1',
    [
      '新增圖片轉文字：手機可拍照掃描或選圖；已存的附件圖片也能辨識；Windows 可選圖或用 Win+Shift+S 截圖後直接辨識。',
      '可框選要辨識的範圍，並依文字位置還原原本的排列（標題 : 內容對齊）。',
      '「在圖上選取文字」：直接在圖片上點選或框選要複製的內容。',
      '辨識結果先顯示可編輯的視窗，確認後插入筆記；全程離線，圖片不會上傳。',
    ],
    [
      'New image to text: scan with the phone camera or pick a photo; saved image attachments can be recognized; on Windows pick an image or use a Win+Shift+S screenshot.',
      'Select the area to recognize, and the original layout (aligned "label : value") is restored from word positions.',
      '"Select text on the image": tap or drag over the picture to choose what to copy.',
      'The result is shown in an editable window before inserting into the note; fully offline, images are never uploaded.',
    ],
  ),
  ChangelogEntry(
    '2.1.3',
    [
      '格式列：編輯時鍵盤上方有標題、粗體、斜體、底線、文字顏色、清單、待辦、引用、程式碼等按鈕。',
      '待辦清單改為小圓框，檢視模式下可直接點選完成；清單按 Enter 自動接下一項。',
      '「圖片」升級為「附件」：新增手寫繪圖（多種筆粗細與顏色、螢光筆、橡皮擦）、影片、即時錄音、錄音檔，與筆記一起加密（影片、錄音單檔上限 30 MB）。',
      '另存新檔：可存成自訂副檔名的文字檔，或整則筆記連同附件打包成 .zip；附件也能單獨另存成原本格式。',
      '貼上 AI／網頁內容時，「Bash」等語言標籤加指令會自動顯示成程式碼框。',
    ],
    [
      'Formatting bar above the keyboard: heading, bold, italic, underline, text color, lists, checklist, quote, code and more.',
      'Round checkboxes you can tick in view mode; Enter continues a list.',
      '"Images" is now "Attachments": handwriting / drawing (pen widths, colors, highlighter, eraser), video, audio recording and audio files, encrypted with the note (30 MB per video / audio file).',
      'Save as file: a text file with any extension, or the whole note with its attachments as a .zip; attachments can also be saved individually in their original format.',
      'Pasted AI / web code that arrives as a language label (e.g. "Bash") plus commands is shown as a code block.',
    ],
  ),
  ChangelogEntry(
    '1.8.4',
    ['從網頁／AI 對話貼上時，「Bash」等語言名稱加指令會自動顯示成程式碼框，可一鍵複製。'],
    ['Pasted code that arrives as a language label plus commands (e.g. "Bash") is now shown as a code block with a copy button.'],
  ),
  ChangelogEntry(
    '1.8.3',
    ['修正 1.8.1／1.8.2 解鎖後無法開啟任何筆記與設定的問題。'],
    ['Fixed notes and Settings not opening after unlock in 1.8.1 / 1.8.2.'],
  ),
  ChangelogEntry(
    '1.8.2',
    [
      'Markdown 預覽新增表格：支援 | 格式的表格，也支援從網頁複製的 Tab 分隔表格。',
      '程式碼區塊改成深色底、等寬字，保留縮排與換行，並有「複製」按鈕，方便貼上 AI 產生的 bash 腳本。',
    ],
    [
      'Markdown preview now renders tables, both | tables and tab-separated tables copied from web pages.',
      'Code blocks use a dark monospace style, keep indentation and line breaks, and have a copy button (handy for AI-generated bash scripts).',
    ],
  ),
  ChangelogEntry(
    '1.8.1',
    [
      '修正第一次開啟時按「不設定密碼，直接使用」沒有反應的問題。',
      '修正鎖定畫面上的對話框（例如從備份檔還原時輸入備份密碼）可能無法開啟的問題。',
    ],
    [
      'Fixed "Use without a password" doing nothing on first launch.',
      'Fixed dialogs on the lock screen (e.g. entering the backup password when restoring) not opening.',
    ],
  ),
  ChangelogEntry(
    '1.8.0',
    [
      '移除 Google Drive 自動同步，改為手動匯出／匯入加密備份檔。',
      '新增語言切換：繁體中文／English（預設跟隨系統）。',
      '設定頁新增版本資訊、版本歷程，並可手動檢查 GitHub 上是否有新版本。',
      '第一次開啟時，可以直接從備份檔還原。',
      '之後的新版本可直接覆蓋安裝，筆記與設定不會消失。',
    ],
    [
      'Removed the automatic Google Drive sync. Use manual encrypted backup export/import instead.',
      'Added a language switch: 繁體中文 / English (follows the system by default).',
      'Settings now show the app version and version history, and can manually check GitHub for a newer version.',
      'On first launch you can restore directly from a backup file.',
      'Future versions install over the old one without losing your notes or settings.',
    ],
  ),
  ChangelogEntry(
    '1.7.0',
    [
      '新增「筆記鎖定」：任一筆記可用獨立的鎖定密碼保護。',
      '新增「不設定主密碼」模式，之後可在設定裡加上或移除主密碼。',
      '已鎖定的筆記不顯示預覽，也不納入密碼檢查。',
    ],
    [
      'Added note locking: protect any note with a separate lock password.',
      'Added a no-master-password mode; you can add or remove a master password later in Settings.',
      'Locked notes show no preview and are excluded from the password check.',
    ],
  ),
  ChangelogEntry(
    '1.6.0',
    [
      '首頁筆記可長按拖曳排序。',
      '每張筆記卡片新增三點選單：釘選、顏色、移到資料夾、刪除等。',
      '設定檔改用原子寫入，避免當機時損毀。',
    ],
    [
      'Long-press and drag notes on the home screen to reorder them.',
      'Each note card has a three-dot menu: pin, color, move to folder, delete and more.',
      'Settings are now written atomically to avoid corruption on crashes.',
    ],
  ),
  ChangelogEntry(
    '1.5.0',
    ['新增主題色（8 色）與深色純黑背景。', '新增 Markdown 預覽。'],
    ['Added 8 theme colors and a pure-black dark background.', 'Added Markdown preview.'],
  ),
  ChangelogEntry('1.4.0', ['新增筆記顏色。'], ['Added note colors.']),
  ChangelogEntry(
    '1.3.0',
    ['Google Drive 備份與同步。', '新增 Windows 版。'],
    ['Google Drive backup and sync.', 'Added a Windows version.'],
  ),
  ChangelogEntry(
    '1.0.0 – 1.2.0',
    [
      '加密筆記與帳號密碼、指紋解鎖、資料夾與標籤、自訂欄位、圖片、CSV 匯入、加密備份匯出與還原、密碼檢查、備份提醒。',
    ],
    [
      'Encrypted notes and logins, fingerprint unlock, folders and tags, custom fields, images, CSV import, encrypted backup export/restore, password check and backup reminders.',
    ],
  ),
];
