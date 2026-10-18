import '../i18n.dart';
enum PwStrength { weak, fair, good, strong }

const Set<String> _commonPasswords = <String>{
  '123456',
  '1234567',
  '12345678',
  '123456789',
  '1234567890',
  '12345',
  '123123',
  '111111',
  '11111111',
  '000000',
  '00000000',
  'password',
  'password1',
  'passw0rd',
  'qwerty',
  'qwerty123',
  'qwertyuiop',
  'abc123',
  'abcd1234',
  '1q2w3e4r',
  'iloveyou',
  'admin',
  'admin123',
  'welcome',
  'letmein',
  'monkey',
  'dragon',
};

/// 粗略的密碼強度評估（在手機上離線計算，不會傳到任何地方）。
PwStrength passwordStrength(String pw) {
  if (pw.isEmpty) return PwStrength.weak;
  if (_commonPasswords.contains(pw.toLowerCase())) return PwStrength.weak;
  if (pw.length < 8) return PwStrength.weak;
  if (pw.split('').toSet().length <= 3) return PwStrength.weak;
  if (RegExp(r'^\d+$').hasMatch(pw) && pw.length < 10) return PwStrength.weak;

  var classes = 0;
  if (RegExp(r'[a-z]').hasMatch(pw)) classes++;
  if (RegExp(r'[A-Z]').hasMatch(pw)) classes++;
  if (RegExp(r'[0-9]').hasMatch(pw)) classes++;
  if (RegExp(r'[^A-Za-z0-9]').hasMatch(pw)) classes++;

  var score = 1; // 長度已 >= 8
  if (pw.length >= 12) score++;
  if (pw.length >= 16) score++;
  if (classes >= 3) score++;
  if (classes == 4) score++;

  if (score <= 1) return PwStrength.weak;
  if (score == 2) return PwStrength.fair;
  if (score == 3) return PwStrength.good;
  return PwStrength.strong;
}

String pwLabel(PwStrength s) {
  switch (s) {
    case PwStrength.weak:
      return tr('偏弱');
    case PwStrength.fair:
      return tr('普通');
    case PwStrength.good:
      return tr('良好');
    case PwStrength.strong:
      return tr('很強');
  }
}
