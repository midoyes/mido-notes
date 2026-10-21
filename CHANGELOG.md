# 更新紀錄

## 2.0.2
- 再次修正格式列：格式列在編輯模式下固定顯示，不會因為輸入框失去焦點而消失；並記住選取範圍，按按鈕時一定套用到你選的文字。

English:
- Formatting bar fix: it now stays visible in edit mode (no longer tied to text-field focus) and remembers the selection so buttons always apply to the selected text.

## 2.0.1
- 修正格式列按鈕按下去後鍵盤與格式列消失、沒有套用格式、也無法選顏色的問題。

English:
- Fixed the formatting bar closing (and doing nothing) when a button was tapped, including the color picker.

## 2.0.0
- 編輯時鍵盤上方新增格式列（像 iPhone 備忘錄）：標題、粗體、斜體、底線、刪除線、文字顏色、項目符號、數字清單、待辦清單、引用、程式碼、連結、分隔線。選取文字再按按鈕即可套用，再按一次取消。
- 待辦清單前面是小圓框；在清單按 Enter 會自動接下一項，空項目再按 Enter 結束清單。
- 在檢視（預覽）模式下，可直接點圓框勾選完成項目，內容會自動儲存。
- 格式仍以 Markdown 文字儲存，舊筆記、備份、另存新檔完全相容。

English:
- New formatting bar above the keyboard (like iPhone Notes): heading, bold, italic, underline, strikethrough, text color, bullets, numbered list, checklist, quote, code, link, divider. Select text and tap to apply; tap again to remove.
- Checklists use round checkboxes; Enter continues the list, Enter on an empty item ends it.
- In view (preview) mode you can tap the circle to check items off; changes are saved automatically.
- Formatting is still stored as Markdown text, so old notes, backups and "Save as file" stay compatible.

## 1.9.0
- 新增「另存新檔」：在筆記右上角選單可把目前筆記存成檔案，自訂檔名與副檔名（.md、.txt、.html、.json…也可自己輸入），並用系統視窗選擇存放位置，手機與電腦都適用。
- 含帳號密碼的筆記存出時會提醒檔案是未加密明文。

English:
- New "Save as file": from the note menu, save the current note as a file with any name and extension (.md, .txt, .html, .json … or type your own) and choose where to store it, on both phone and PC.
- Notes containing logins show a warning that the saved file is unencrypted plain text.

## 1.8.4
- 從網頁／AI 對話複製貼上時，若程式碼只剩「Bash」等語言名稱加指令（沒有 ``` 標記），預覽會自動還原成程式碼框，並可一鍵複製。

English:
- When pasting from web pages / AI chats, code that arrives as a language label (e.g. "Bash") followed by commands, without ``` fences, is now auto-rendered as a code block with a copy button.

## 1.8.3
- 修正 1.8.1／1.8.2 解鎖後無法開啟任何筆記與設定的問題（Windows、Android 都會發生）。

English:
- Fixed notes and Settings not opening after unlock in 1.8.1 / 1.8.2 (affected Windows and Android).

## 1.8.2
- Markdown 預覽新增表格：支援 `|` 格式的表格，也支援從網頁複製的 Tab 分隔表格。
- 程式碼區塊改成深色底、等寬字，保留縮排與換行，並有「複製」按鈕，方便貼上 AI 產生的 bash 腳本。

English:
- Markdown preview now renders tables, both `|` tables and tab-separated tables copied from web pages.
- Code blocks use a dark monospace style, keep indentation and line breaks, and have a copy button (handy for AI-generated bash scripts).

## 1.8.1
- 修正第一次開啟時按「不設定密碼，直接使用」沒有反應的問題。
- 修正鎖定畫面上的對話框（例如從備份檔還原時輸入備份密碼）可能無法開啟的問題。

English:
- Fixed "Use without a password" doing nothing on first launch.
- Fixed dialogs on the lock screen (e.g. entering the backup password when restoring) not opening.

## 1.8.0
- 移除 Google Drive 自動同步，改為手動匯出／匯入加密備份檔。
- 新增語言切換：繁體中文／English（預設跟隨系統）。
- 設定頁新增版本資訊、版本歷程，並可手動檢查 GitHub 上是否有新版本。
- 第一次開啟時，可以直接從備份檔還原。
- 之後的新版本可直接覆蓋安裝，筆記與設定不會消失。

English:
- Removed the automatic Google Drive sync; use manual encrypted backup export/import.
- Added a language switch: 繁體中文 / English (follows the system by default).
- Settings show the app version and version history, and can manually check GitHub for updates.
- On first launch you can restore directly from a backup file.
- Future versions install over the old one without losing notes or settings.

## 1.7.0
- 新增「筆記鎖定」：任一筆記的選項裡可以鎖定，開啟、快速複製、刪除前都要輸入「鎖定密碼」。
- 鎖定密碼和登入主密碼互相獨立，可以不同；在「設定 → 筆記鎖定密碼」設定、更改或移除。
- 新增「不設定主密碼」：第一次使用可選擇直接進入；之後可在設定裡加上或移除主密碼。
- 已鎖定的筆記不顯示內容預覽、搜尋只比對標題、不納入密碼檢查。

## 1.6.0
- 首頁筆記可長按拖曳排序（自訂排序，只存在本機）。
- 每張筆記卡片右側新增三點選單：釘選、顏色、移到資料夾、刪除等。
- 設定檔改用原子寫入，避免當機時損毀。

## 1.5.0
- 新增主題色（8 色）與深色純黑背景。
- 新增 Markdown 預覽。

## 1.4.0
- 新增筆記顏色。

## 1.3.0
- Google Drive 備份與同步（手機與電腦共用）。
- 新增 Windows 版。

## 1.0.0 ~ 1.2.0
- 加密筆記與帳號密碼、指紋解鎖、資料夾與標籤、自訂欄位、圖片、
  CSV 匯入、加密備份匯出與還原、密碼檢查、備份提醒。
