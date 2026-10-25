# 更新紀錄

## 2.6.3
改進：
- Android 安裝檔只包含 64 位元 ARM（arm64-v8a，現今手機皆適用），檔案大小約縮小一半；文字辨識（含 AI 辨識）與所有功能不變。
- 修正 GitHub Actions 建置結尾偶爾出現「No space left on device」造成紅色 X 的問題（建置前先釋放磁碟空間、不再快取 Flutter），APK 不再因此顯示錯誤。

English:
Improvements:
- The Android APK now includes only 64-bit ARM (arm64-v8a, used by current phones), roughly halving its size; text recognition (including AI recognition) and all features are unchanged.
- Fixed the GitHub Actions build occasionally ending with "No space left on device" and a red X (frees disk space before building and no longer caches Flutter), so the APK build no longer shows an error.

## 2.6.2
新功能：
- 筆記內搜尋：按「上一個／下一個」跳到每個吻合的關鍵字時，會捲到畫面正中央並以深色標示；從首頁搜尋點進記事本，第一個吻合處也置中。Windows 與 Android 都適用。
- 首頁長按記事本會跳出與右上角「⋮」相同的選單；繼續按住並拖動，仍可自由移動記事本在首頁的位置（選單會自動收起）。搜尋結果中長按也能開選單。
- 新增「複製到資料夾」：選一個資料夾（或不分類），複製出一份新的記事本並自動命名（「原名 複製」，重複時加編號），附件也會一併複製。「移到資料夾」維持原本功能。

English:
New features:
- In-note search: Previous / Next now scroll every match to the vertical center of the screen with a stronger highlight; the first match is centered too when you open a note from the home-screen search. Works on Windows and Android.
- Long-pressing a note on the home screen opens the same menu as the top-right "⋮"; keep holding and drag to move the note's position as before (the menu closes automatically). Long-press also works on search results.
- New "Copy to folder": pick a folder (or none) to make a copy of the note with an automatic name ("Name Copy", numbered if it already exists); attachments are copied too. "Move to folder" works as before.

## 2.5.1
新功能：
- 圖片轉文字新增「AI 辨識（PaddleOCR）」，Windows 與 Android 都支援：
  - 內建離線模型，預設使用；對路徑、程式碼、英文與符號多的畫面、拍螢幕的照片，辨識明顯更準確。
  - 可在辨識視窗的「辨識引擎」切回標準（Windows 內建 OCR／手機 ML Kit）；AI 辨識失敗時會自動改用標準引擎。
  - 辨識後的文字依原本位置排列，並可直接在圖片上點選或框選要複製的內容。
  - 全程在本機離線完成，圖片不會上傳。
- 注意：因為內建 AI 模型，Android 安裝檔與 Windows 壓縮檔會比以前大不少。

English:
New features:
- Image to text now has "AI recognition (PaddleOCR)" on both Windows and Android:
  - A bundled offline model, used by default; clearly more accurate on paths, code, English / symbol-heavy screens and photos of screens.
  - Switch back to Standard (Windows built-in OCR / ML Kit on phones) under "Engine" in the recognition window; if AI recognition fails the app falls back to Standard automatically.
  - Recognized text keeps its original layout, and you can tap or drag on the picture to copy only what you need.
  - Everything runs offline on your device; images are never uploaded.
- Note: because the AI model is bundled, the Android APK and the Windows zip are noticeably larger than before.

## 2.3.1
新功能：
- 新增「圖片轉文字」：
  - 手機：可直接拍照掃描，或從相簿選圖；已存成附件的圖片，開啟後按右上角按鈕也能辨識。
  - Windows：選擇圖片檔、對附件圖片辨識，或用 Win+Shift+S 截圖後直接「剪貼簿截圖轉文字」。
  - 可「框選要辨識的範圍」，只辨識需要的那一塊。
  - 依文字位置還原原本的排列（標題 : 內容對齊的表格、終端機畫面），對齊的內容插入筆記時自動放進程式碼區塊。
  - 「在圖上選取文字」：直接在圖片上點單字或拖曳框選，只複製或帶回要的內容。
  - Windows 提供自動模式（試多種影像處理與語言並挑最好的）、加強影像、反相等選項。
  - 辨識結果先顯示在可編輯的視窗，確認後再插入筆記；可選擇同時把照片存成附件。
  - 全程在本機離線完成，圖片不會上傳。

English:
New features:
- New "Image to text":
  - Phone: scan with the camera or pick a photo; for an image already saved as an attachment, open it and tap the button at the top right.
  - Windows: pick an image file, run it on a saved attachment, or use "Clipboard screenshot to text" after a Win+Shift+S capture.
  - "Select area to recognize" to crop to just the part you need.
  - Restores the original layout from word positions (aligned "label : value" tables, terminal screens); aligned text is inserted into a code block.
  - "Select text on the image": tap words or drag a box on the picture to copy or bring back only what you want.
  - Windows has an Auto mode (tries several image treatments and languages and keeps the best), plus Enhance and Invert options.
  - The result is shown in an editable window first; insert it when you are happy, and optionally keep the photo as an attachment.
  - Everything runs offline on your device; images are never uploaded.

## 2.1.3
新功能：
- **格式列**：編輯時鍵盤上方出現一排按鈕（像 iPhone 備忘錄）：標題、粗體、斜體、底線、刪除線、文字顏色、項目符號、數字清單、待辦清單、引用、程式碼、連結、分隔線。
- **待辦清單**：前面是小圓框，在檢視模式下點一下就能勾選完成；按 Enter 自動接下一項。
- **附件**：筆記下方的「圖片」區升級為「附件」，除了相片，還可加入：
  - **手寫繪圖**：多種筆粗細、9 種顏色、螢光筆、橡皮擦、復原／重做。
  - **影片**：從相簿或檔案選擇，手機也可直接錄影。
  - **即時錄音**（最長 10 分鐘）與**錄音檔**。
  - 附件與筆記一起加密，單一影片或錄音上限 30 MB；點選後以系統播放器播放。
- **另存新檔**：把筆記存成文字檔（可自訂副檔名，如 .md、.txt、.html），或**整則筆記連同附件打包成 .zip**；每個附件也能單獨另存成原本格式。
- Markdown 預覽：貼上 AI／網頁內容時，「Bash」等語言標籤加指令會自動顯示成程式碼框。

English:
New features:
- **Formatting bar**: a row of buttons above the keyboard while editing (like iPhone Notes): heading, bold, italic, underline, strikethrough, text color, bullets, numbered list, checklist, quote, code, link, divider.
- **Checklists**: round checkboxes you can tick in view mode; Enter continues the list.
- **Attachments**: the "Images" area is now "Attachments". Besides photos you can add:
  - **Handwriting / drawing**: several pen widths, 9 colors, highlighter, eraser, undo / redo.
  - **Video**: from gallery or files, or record on your phone.
  - **Audio recording** (up to 10 minutes) and **audio files**.
  - Attachments are encrypted with the note; video / audio are limited to 30 MB each and play with the system player.
- **Save as file**: save a note as a text file (any extension, e.g. .md, .txt, .html) or **pack the whole note with its attachments into a .zip**; each attachment can also be saved on its own in its original format.
- Markdown preview: pasted AI / web content where code arrives as a language label (e.g. "Bash") plus commands is shown as a code block.

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
