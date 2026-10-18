/// App 內建的版本歷程（離線也看得到）。新增版本時，請同步更新 CHANGELOG.md。
class ChangelogEntry {
  const ChangelogEntry(this.version, this.zh, this.en);

  final String version;
  final List<String> zh;
  final List<String> en;
}

const List<ChangelogEntry> kChangelog = <ChangelogEntry>[
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
