import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import '../data/password_tools.dart';
import 'editor_screen.dart';
import '../i18n.dart';

class _Entry {
  _Entry(this.note, this.cred);

  final Note note;
  final Credential cred;
}

/// 密碼檢查：找出重複使用與強度偏弱的密碼。全部在手機上離線計算，畫面上不會顯示任何密碼。
class SecurityCheckScreen extends StatelessWidget {
  const SecurityCheckScreen({super.key});

  void _open(BuildContext context, Note n) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EditorScreen(noteId: n.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final entries = <_Entry>[];
        for (final n in vault.notes) {
          if (n.isTrashed || n.locked || n.type != NoteType.login) continue;
          for (final c in n.credentials) {
            if (c.password.isNotEmpty) entries.add(_Entry(n, c));
          }
        }

        final byPw = <String, List<_Entry>>{};
        for (final e in entries) {
          byPw.putIfAbsent(e.cred.password, () => <_Entry>[]).add(e);
        }
        final reused = byPw.values.where((l) => l.length > 1).toList()
          ..sort((a, b) => b.length.compareTo(a.length));
        final reusedAccounts = reused.fold<int>(0, (s, l) => s + l.length);
        final weak = entries
            .where((e) => passwordStrength(e.cred.password) == PwStrength.weak)
            .toList();

        final cs = Theme.of(context).colorScheme;
        final tt = Theme.of(context).textTheme;
        final allGood = entries.isNotEmpty && reused.isEmpty && weak.isEmpty;

        return Scaffold(
          appBar: AppBar(title: Text(tr('密碼檢查'))),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Card(
                margin: EdgeInsets.zero,
                color: allGood ? cs.primaryContainer : cs.surfaceContainerLow,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tr('檢查了 ${entries.length} 組帳號密碼'), style: tt.titleMedium),
                      const SizedBox(height: 8),
                      if (entries.isEmpty)
                        Text(tr('還沒有帳號密碼可以檢查。'))
                      else if (allGood)
                        Text(tr('沒有發現重複或偏弱的密碼，很棒！'))
                      else ...[
                        Text(tr('重複使用：${reused.length} 組密碼，涉及 $reusedAccounts 個帳號')),
                        Text(tr('強度偏弱：${weak.length} 組')),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        tr('檢查在手機上離線進行，不會把密碼傳到任何地方。已鎖定的筆記不會被檢查。'),
                        style: tt.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
              if (reused.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(tr('重複使用的密碼'), style: tt.titleSmall),
                const SizedBox(height: 4),
                Text(
                  tr('同一個密碼被用在多個帳號，只要其中一個外洩，其他帳號都有風險。建議各自改成不同的密碼。'),
                  style: tt.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final group in reused)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: cs.surfaceContainerLow,
                    child: ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: Icon(Icons.content_copy, color: cs.error),
                      title: Text(tr('同一個密碼用在 ${group.length} 個帳號')),
                      children: [
                        for (final e in group)
                          ListTile(
                            dense: true,
                            title: Text(
                              e.note.displayTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              e.cred.username.isEmpty ? tr('（未填帳號）') : e.cred.username,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _open(context, e.note),
                          ),
                      ],
                    ),
                  ),
              ],
              if (weak.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text(tr('強度偏弱的密碼'), style: tt.titleSmall),
                const SizedBox(height: 4),
                Text(
                  tr('太短、太常見或字元種類太少。建議改成 12 個字元以上，並混合大小寫、數字與符號（編輯畫面可以用「產生密碼」）。'),
                  style: tt.bodySmall,
                ),
                const SizedBox(height: 8),
                for (final e in weak)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    color: cs.surfaceContainerLow,
                    child: ListTile(
                      leading: Icon(Icons.warning_amber_rounded, color: cs.error),
                      title: Text(
                        e.note.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        tr('${e.cred.username.isEmpty ? tr('（未填帳號）') : e.cred.username}　長度 ${e.cred.password.length}'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _open(context, e.note),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}
