# Mido Notes / Mido筆記

Encrypted notes and password manager for Android and Windows, built with Flutter.
加密筆記與帳號密碼本（Android／Windows），使用 Flutter 開發，由 GitHub Actions 自動編譯。

**Download / 下載**: see the [Releases](../../releases) page — `Mido-notes.apk` (Android) or `Mido-notes-windows.zip` (Windows).
請到 [Releases](../../releases) 頁面下載：`Mido-notes.apk`（Android）或 `Mido-notes-windows.zip`（Windows，解壓縮後執行）。

---

## Features / 功能

- Text notes and logins (site / username / password / notes), several accounts per login note
  文字筆記與帳號密碼（網站／帳號／密碼／備註），一筆登入資料可放多組帳號
- Folders, tags, pin, color, drag-to-reorder, search, image attachments (encrypted)
  資料夾、標籤、釘選、顏色、拖曳排序、搜尋、圖片附件（加密儲存）
- **Markdown preview** — headings, bold / italic, lists, to-do, quotes, links, **tables**, and **code blocks with a copy button**; pasted AI / web content (e.g. a "Bash" label followed by commands) is recognized as a code block automatically
  **Markdown 預覽**：標題、粗斜體、清單、待辦、引用、連結、**表格**、**程式碼區塊（附複製按鈕）**；從 AI／網頁貼上的內容（例如「Bash」標籤加指令）會自動辨識成程式碼區塊
- Per-note lock with its own lock password; optional "no master password" mode
  單筆筆記可另設鎖定密碼；也可選擇「不設定主密碼」模式
- Trash (30 days), password generator, reused / weak password check, Chrome / Google CSV import
  回收桶（30 天）、密碼產生器、重複／弱密碼檢查、匯入 Chrome／Google 密碼 CSV
- Encrypted backup export / restore — manual, no cloud service is used
  加密備份匯出／還原：完全手動，不使用任何雲端服務
- Fingerprint unlock, screenshot blocking, auto-lock
  指紋解鎖、禁止截圖、自動鎖定
- **Traditional Chinese / English** (follows the system language, or choose in Settings)
  **繁體中文／English**（預設跟隨系統語言，可在設定中手動切換）
- Light / dark / pure black, 8 theme colors
  淺色／深色／純黑、8 種主題色
- **In-app version history** and **manual "check for updates"** (only contacts GitHub when you tap it)
  **App 內版本歷程**與**手動「檢查更新」**（只有按下時才會連線 GitHub）
- **Update by installing over the old version** — your notes and settings are kept (Android: same signing key required)
  **新版本可直接覆蓋安裝**，筆記與設定不會消失（Android 需使用相同簽署金鑰）

## What's new / 新版本重點

| Version | Highlights / 重點 |
|---|---|
| 1.8.4 | Auto-detect pasted code blocks (language label + commands) / 貼上的程式碼（語言標籤＋指令）自動辨識成程式碼框 |
| 1.8.3 | Fixed notes and Settings not opening after unlock / 修正解鎖後無法開啟筆記與設定 |
| 1.8.2 | Markdown tables and code blocks with copy button; first-run fixes / 表格與程式碼區塊（可複製）、首次開啟修正 |
| 1.8.1 | Fixed the "no master password" button on first launch / 修正首次開啟「不設定密碼」按鈕沒反應 |
| 1.8.0 | Cloud sync removed (manual backup only), English UI, in-app version history, manual update check / 移除雲端同步（僅手動備份）、英文介面、App 內版本歷程、手動檢查更新 |

Full history: [CHANGELOG.md](CHANGELOG.md) or **Settings → About → Version history** in the app.
完整紀錄請見 [CHANGELOG.md](CHANGELOG.md)，或 App 內「設定 → 關於 → 版本歷程」。

---

## Security design / 安全設計

- Random 256-bit data key (DEK) encrypts everything with AES-256-GCM.
  以隨機 256 位元資料金鑰（DEK）搭配 AES-256-GCM 加密所有內容。
- The master password goes through PBKDF2-HMAC-SHA256 (400,000 rounds) and only wraps the DEK.
  主密碼經 PBKDF2-HMAC-SHA256（40 萬次）處理，只用來包覆 DEK。
- Everything stays on the device. The app never uploads your data; the only network call is the optional manual update check to the GitHub API.
  資料全部留在你的裝置上，App 不會上傳任何資料；唯一的網路連線是你手動按下的檢查更新（GitHub API）。
- **If you forget the master password there is no recovery and no backdoor.**
  **忘記主密碼就無法復原，也沒有任何後門。**
- Not independently audited. Use at your own risk. 自製 App，未經第三方資安審計，請自行評估風險。

## Privacy / 隱私

No accounts, no analytics, no ads, no cloud sync. Backups are files you export yourself.
沒有帳號、沒有統計分析、沒有廣告、沒有雲端同步。備份是你自己匯出的檔案。

---

## Forks and contributions / Fork 與貢獻

Forking is safe for the original project. A fork is an independent copy under the forker's own account:
Fork 對原專案是安全的。Fork 是在對方帳號下的獨立複本：

- Pushing to a fork **never** changes this repository. Others can only send a Pull Request, and nothing is merged unless the owner approves it.
  推送到 fork **不會**改到本專案；別人只能送 Pull Request，擁有者同意合併才會生效。
- Repository **Secrets (signing key) are not copied** to forks, and are not available to workflows triggered by pull requests from forks.
  本專案的 **Secrets（簽署金鑰）不會被複製**到 fork，來自 fork 的 Pull Request 也無法取得。
- Only the owner and invited collaborators can push to this repository.
  只有擁有者與受邀的協作者能直接推送到本專案。

Security issues: please open a private report or an Issue without publishing sensitive details.
資安問題請以私訊或 Issue 回報，請勿公開敏感細節。

---

## Build it yourself / 自行編譯

1. Fork or copy this repository. 先 Fork 或複製本專案到自己的帳號。
2. (Recommended) create your own Android signing key and add four Actions secrets in
   **Settings → Secrets and variables → Actions**: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`.
   Without them the APK is signed with a temporary debug key, and a later build cannot be installed over it.
   Keep the key file safe and never commit it.
   （建議）自行建立 Android 簽署金鑰，並在 **Settings → Secrets and variables → Actions** 新增四個 Secrets：`KEYSTORE_BASE64`、`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`。
   沒設定的話 APK 會用臨時金鑰簽署，之後的版本就無法覆蓋安裝。金鑰檔請妥善保管，切勿上傳到 repo。
3. Run the **Build APK** / **Build Windows** workflows (Actions tab) or push to `main` **of your own fork**.
   Each run publishes a GitHub Release tagged `v<version in pubspec.yaml>`.
   在 Actions 頁籤執行 **Build APK**／**Build Windows**，或推送到**你自己 fork 的** `main`。每次執行都會發佈一個標籤為 `v<pubspec.yaml 的版本>` 的 GitHub Release。

   > In a fork, Actions are disabled by default — open the Actions tab and click "Enable".
   > Fork 預設不會啟用 Actions，請到 Actions 頁籤按「Enable」。

To publish a new version: raise `version:` in `pubspec.yaml` (the number after `+` must increase every time), add a section to `CHANGELOG.md`, and push.
要發佈新版本：提高 `pubspec.yaml` 的 `version:`（`+` 後的數字每次都要變大），在 `CHANGELOG.md` 加一段說明，然後推送。

> If you fork this app, change `kRepo` in `lib/update.dart` to your own repository, otherwise "check for updates" will look at the original project.
> 若你 fork 並自行發佈，請把 `lib/update.dart` 裡的 `kRepo` 改成你自己的 repo，否則「檢查更新」會查詢原專案。

## Project layout / 專案結構

```
lib/                   Flutter source / 程式碼（UI 在 lib/ui，資料與加密在 lib/data、lib/crypto）
lib/i18n*.dart         tr() translation helper + Chinese→English table / 翻譯函式與中英對照表
android_overlay/       Native Android files (biometrics, screenshot blocking) / Android 原生檔案
tool/                  Scripts that patch the generated Android / Windows projects / 修補自動產生專案的腳本
.github/workflows/     Cloud build definitions / 雲端編譯設定
```

## License / 授權

MIT — see [LICENSE](LICENSE). 採用 MIT 授權，詳見 [LICENSE](LICENSE)。
