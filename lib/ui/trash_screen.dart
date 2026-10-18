import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import 'common.dart';
import '../i18n.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  String _title(Note n) {
    final t = n.title.trim();
    if (t.isNotEmpty) return t;
    if (n.type == NoteType.login) return n.site.isNotEmpty ? n.site : tr('未命名帳號');
    return tr('無標題');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: vault,
      builder: (context, _) {
        final items = vault.notes.where((n) => n.isTrashed).toList()
          ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('回收桶')),
            actions: [
              if (items.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: tr('清空回收桶'),
                      message: tr('共 ${items.length} 項內容會被永久刪除，無法復原。'),
                      confirmText: tr('永久刪除'),
                      danger: true,
                    );
                    if (ok) vault.emptyTrash();
                  },
                  child: Text(tr('清空')),
                ),
            ],
          ),
          body: items.isEmpty
              ? Center(child: Text(tr('回收桶是空的')))
              : ListView(
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(tr('回收桶內的項目會在 30 天後自動永久刪除。')),
                    ),
                    for (final n in items)
                      ListTile(
                        leading: Icon(
                          n.type == NoteType.login ? Icons.key : Icons.sticky_note_2_outlined,
                        ),
                        title: Text(_title(n), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(tr('刪除於 ${fmtDate(n.deletedAt!, full: true)}')),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'restore') {
                              vault.restore(n.id);
                            } else if (v == 'delete') {
                              final ok = await confirmDialog(
                                context,
                                title: tr('永久刪除'),
                                message: tr('這項內容會被永久刪除，無法復原。'),
                                confirmText: tr('永久刪除'),
                                danger: true,
                              );
                              if (ok) vault.deleteForever(n.id);
                            }
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'restore', child: Text(tr('還原'))),
                            PopupMenuItem(value: 'delete', child: Text(tr('永久刪除'))),
                          ],
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }
}
