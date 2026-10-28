/// Google OAuth 設定（Google Cloud 專案「Mido Notes」）。
///
/// Client ID 與 installed-app 的 client secret 依 Google 規範都不是機密，
/// 可以放在公開原始碼裡。權限範圍只有 drive.appdata（App 專用的隱藏資料夾）。
///
/// 兩個平台都用「電腦版應用程式」類型的用戶端，走系統瀏覽器 + 本機迴路位址（loopback）+ PKCE 登入。
const String kGoogleClientId =
    '748969109709-80ilc76qj8q7hdnt3ts4qc6bv6ai4v5t.apps.googleusercontent.com';

/// Google Cloud「Mido Notes Windows」用戶端的 Client secret。
/// 不寫在原始碼裡：建置時由 GitHub Actions 的 secret `GOOGLE_CLIENT_SECRET`
/// 以 --dart-define 帶入（避免被掃描機制當成外洩的密鑰）。
const String kGoogleClientSecret = String.fromEnvironment('GOOGLE_CLIENT_SECRET');

const String kGoogleScope = 'https://www.googleapis.com/auth/drive.appdata';

/// 雲端硬碟隱藏資料夾裡的同步檔名稱。
const String kSyncFileName = 'mido_notes_sync.mdbk';
