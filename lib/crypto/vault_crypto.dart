import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// 加密工具：AES-256-GCM（資料）＋ PBKDF2-HMAC-SHA256（由主密碼推導金鑰）。
///
/// 輸出格式為 nonce(12) + ciphertext + mac(16)。
class VaultCrypto {
  VaultCrypto._();

  static const int kdfIterations = 400000;
  static const int saltLength = 16;
  static const int _nonceLength = 12;
  static const int _macLength = 16;

  static final AesGcm _aes = AesGcm.with256bits();
  static final Random _rng = Random.secure();

  static Uint8List randomBytes(int n) =>
      Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

  /// 由主密碼推導「金鑰加密金鑰」(KEK)。
  static Future<SecretKey> deriveKey(
    String password,
    List<int> salt,
    int iterations,
  ) {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: 256,
    );
    return pbkdf2.deriveKeyFromPassword(password: password, nonce: salt);
  }

  /// 產生隨機的資料金鑰 (DEK)。
  static Future<SecretKey> newDataKey() => _aes.newSecretKey();

  static Future<Uint8List> encrypt(List<int> plain, SecretKey key) async {
    final box = await _aes.encrypt(plain, secretKey: key);
    return box.concatenation();
  }

  /// 解密；金鑰錯誤或資料被竄改時會丟出例外。
  static Future<Uint8List> decrypt(List<int> data, SecretKey key) async {
    final box = SecretBox.fromConcatenation(
      data,
      nonceLength: _nonceLength,
      macLength: _macLength,
    );
    final plain = await _aes.decrypt(box, secretKey: key);
    return Uint8List.fromList(plain);
  }
}
