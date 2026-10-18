import 'data/app_settings.dart';
import 'data/vault_store.dart';

/// 全域單例：加密資料庫與（非敏感的）App 設定。
final VaultStore vault = VaultStore();
final AppSettings appSettings = AppSettings();
