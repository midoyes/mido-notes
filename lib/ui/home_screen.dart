import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/models.dart';
import 'backup_screen.dart';
import 'common.dart';
import 'editor_screen.dart';
import 'settings_screen.dart';
import 'trash_screen.dart';
import '../i18n.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // all | text | login | trash | folder:<id> | tag:<名稱>
  String _filter = 'all';
  bool _searching = false;
  final TextEditingController _search = TextEditingController();

  final ScrollController _scroll = ScrollController();
  final GlobalKey _viewKey = GlobalKey();
  Timer? _autoTimer;
  double _scrollSpeed = 0;

  // 長按記事本：先跳出和右上角「⋮」相同的選單；繼續按住並拖動就變成一般的移動（選單自動收起）
  Offset _pressPos = Offset.zero; // 最近一次手指／滑鼠按下的位置
  Offset? _dragOrigin;

  // 選單用 Overlay 自己畫（不開新頁面），這樣長按後繼續拖動時，下面的記事本仍然收得到「放開」事件，
  // 才能照常移動排序位置。
  OverlayEntry? _menuEntry;
  final ValueNotifier<bool> _holding = ValueNotifier<bool>(false);

  void _showNoteMenu(Note n, Offset pos, {required bool holding}) {
    if (n.isTrashed || !mounted) return;
    _closeNoteMenu();
    _holding.value = holding;
    final items = noteMenuItems(n);
    final size = MediaQuery.of(context).size;
    const w = 248.0;
    final h = items.length * 48.0 + 16;
    var left = pos.dx;
    if (left > size.width - w - 8) left = size.width - w - 8;
    if (left < 8) left = 8;
    var top = pos.dy;
    if (top > size.height - h - 8) top = size.height - h - 8;
    if (top < 8) top = 8;
    _menuEntry = OverlayEntry(
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Stack(
          children: [
            // 點選單以外的地方關閉選單（還在按住拖動的時候不攔截，讓拖曳照常進行）
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: _holding,
                builder: (_, hold, __) => IgnorePointer(
                  ignoring: hold,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _closeNoteMenu,
                    onSecondaryTap: _closeNoteMenu,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: w,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                color: cs.surfaceContainerHigh,
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final it in items)
                        InkWell(
                          onTap: () {
                            _closeNoteMenu();
                            _menuAction(n, it.key);
                          },
                          child: SizedBox(
                            height: 48,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(it.value, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_menuEntry!);
  }

  void _closeNoteMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
  }

  @override
  void dispose() {
    _closeNoteMenu();
    _holding.dispose();
    _autoTimer?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _dragStart() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_scrollSpeed == 0 || !_scroll.hasClients) return;
      final p = _scroll.position;
      _scroll.jumpTo(
        (p.pixels + _scrollSpeed).clamp(p.minScrollExtent, p.maxScrollExtent),
      );
    });
  }

  void _dragMove(Offset global) {
    final box = _viewKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final y = box.globalToLocal(global).dy;
    final h = box.size.height;
    const edge = 80.0;
    if (y < edge) {
      _scrollSpeed = -(edge - y) / edge * 18;
    } else if (y > h - edge) {
      _scrollSpeed = (y - (h - edge)) / edge * 18;
    } else {
      _scrollSpeed = 0;
    }
  }

  void _dragEnd() {
    _autoTimer?.cancel();
    _autoTimer = null;
    _scrollSpeed = 0;
  }

  /// 把 [dragId] 移到 [targetId] 的位置，並存成自訂排序。
  void _reorder(List<Note> visible, String dragId, String targetId) {
    final ids = visible.map((n) => n.id).toList();
    final from = ids.indexOf(dragId);
    final to = ids.indexOf(targetId);
    if (from < 0 || to < 0 || from == to) return;
    ids.removeAt(from);
    ids.insert(to, dragId);

    final active = vault.notes.where((n) => !n.isTrashed).toList();
    final alive = active.map((n) => n.id).toSet();
    List<String> g;
    if (appSettings.sortKey == 'manual') {
      final known = appSettings.manualOrder.where(alive.contains).toList();
      final knownSet = known.toSet();
      final unknown = [
        for (final n in visible)
          if (!knownSet.contains(n.id)) n.id,
      ];
      g = [...unknown, ...known];
    } else {
      active.sort(_comparator());
      g = active.map((n) => n.id).toList();
    }
    final vs = ids.toSet();
    var k = 0;
    for (var i = 0; i < g.length; i++) {
      if (vs.contains(g[i]) && k < ids.length) g[i] = ids[k++];
    }
    appSettings.setManualOrder(g);
  }

  Widget _card(List<Note> notes, int i, bool grid) {
    final n = notes[i];
    final card = _NoteCard(
      note: n,
      grid: grid,
      onTap: () => _openNote(n),
      onMenu: (a) => _menuAction(n, a),
    );
    if (n.isTrashed) return card;
    if (_searching) {
      // 搜尋結果不能排序，但長按一樣可以跳出選單
      return GestureDetector(
        onLongPressStart: (d) => _showNoteMenu(n, d.globalPosition, holding: false),
        child: card,
      );
    }
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => d.data != n.id,
      onAcceptWithDetails: (d) => _reorder(notes, d.data, n.id),
      builder: (ctx, cand, _) {
        final hot = cand.isNotEmpty;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) => _pressPos = e.position,
          child: LongPressDraggable<String>(
          data: n.id,
          dragAnchorStrategy: pointerDragAnchorStrategy,
          onDragStarted: () {
            _dragStart();
            _dragOrigin = null;
            _showNoteMenu(n, _pressPos, holding: true);
          },
          onDragUpdate: (d) {
            _dragMove(d.globalPosition);
            _dragOrigin ??= d.globalPosition;
            if ((d.globalPosition - _dragOrigin!).distance > 12) _closeNoteMenu();
          },
          onDragEnd: (_) {
            _dragEnd();
            _dragOrigin = null;
            _holding.value = false; // 放開了：選單若還在，就可以點選或點外面關閉
          },
          feedback: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: Theme.of(ctx).colorScheme.primaryContainer,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  n.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.3, child: card),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: hot
                  ? Border.all(color: Theme.of(ctx).colorScheme.primary, width: 3)
                  : null,
            ),
            child: card,
          ),
        ),
        );
      },
    );
  }

  Future<void> _menuAction(Note n, String a) async {
    switch (a) {
      case 'copy':
        if (await ensureNoteAccess(context, n)) _quickCopy(n);
      case 'lock':
        await toggleNoteLock(context, n);
      case 'pin':
        vault.setPinned(n.id, !n.pinned);
      case 'color':
        final c = await pickNoteColor(context, n.color);
        if (c != null) vault.setColor(n.id, c);
      case 'folder':
        final r = await pickFolder(context, current: n.folderId);
        if (r != null) vault.moveToFolder(n.id, r.isEmpty ? null : r);
      case 'duplicate':
        if (!await ensureNoteAccess(context, n)) return;
        if (!mounted) return;
        final dst = await pickFolder(
          context,
          current: n.folderId,
          title: tr('複製到資料夾'),
        );
        if (dst == null || !mounted) return;
        final copy = await vault.duplicateNote(n, dst.isEmpty ? null : dst);
        if (copy != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('已複製為「${copy.displayTitle}」'))),
          );
        }
      case 'trash':
        if (await ensureNoteAccess(context, n)) _trash(n);
    }
  }

  String? get _currentFolderId =>
      _filter.startsWith('folder:') ? _filter.substring(7) : null;

  String? get _currentTag =>
      _filter.startsWith('tag:') ? _filter.substring(4) : null;

  /// 搜尋會比對的文字：標題、內文、網站、帳號、標籤、自訂欄位（隱藏的欄位內容不比對）。
  Iterable<String> _searchTexts(Note n) sync* {
    yield n.title;
    if (n.locked) return; // 鎖定的筆記只比對標題
    yield n.body;
    yield n.site;
    for (final c in n.credentials) {
      yield c.username;
    }
    for (final t in n.tags) {
      yield t;
    }
    for (final f in n.fields) {
      yield f.label;
      if (!f.secret) yield f.value;
    }
  }

  int Function(Note, Note) _comparator() {
    final key = appSettings.sortKey;
    final asc = appSettings.sortAsc;
    final pinTop = appSettings.pinTop;
    final order = <String, int>{
      for (var i = 0; i < appSettings.manualOrder.length; i++)
        appSettings.manualOrder[i]: i,
    };
    return (a, b) {
      if (pinTop && a.pinned != b.pinned) return a.pinned ? -1 : 1;
      if (key == 'manual') {
        final ia = order[a.id] ?? -1;
        final ib = order[b.id] ?? -1;
        if (ia != ib) return ia.compareTo(ib);
        return b.updatedAt.compareTo(a.updatedAt);
      }
      int c;
      switch (key) {
        case 'created':
          c = a.createdAt.compareTo(b.createdAt);
        case 'title':
          c = a.displayTitle
              .toLowerCase()
              .compareTo(b.displayTitle.toLowerCase());
        default:
          c = a.updatedAt.compareTo(b.updatedAt);
      }
      return asc ? c : -c;
    };
  }

  List<Note> _visible() {
    final q = _search.text.trim().toLowerCase();
    final inTrash = _filter == 'trash';
    Iterable<Note> list = vault.notes.where((n) => n.isTrashed == inTrash);
    if (q.isNotEmpty) {
      // 搜尋時不受分類限制，一次搜尋全部（回收桶分類則只搜回收桶）。
      list = list.where(
        (n) => _searchTexts(n).any((s) => s.toLowerCase().contains(q)),
      );
    } else if (_filter == 'login') {
      list = list.where((n) => n.type == NoteType.login);
    } else if (_filter == 'text') {
      list = list.where((n) => n.type == NoteType.note);
    } else if (_currentFolderId != null) {
      list = list.where((n) => n.folderId == _currentFolderId);
    } else if (_currentTag != null) {
      list = list.where((n) => n.tags.contains(_currentTag));
    }
    final out = list.toList();
    if (inTrash) {
      out.sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));
    } else {
      out.sort(_comparator());
    }
    return out;
  }

  void _openNew(NoteType type) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(newType: type, folderId: _currentFolderId),
      ),
    );
  }

  Future<void> _openNote(Note n) async {
    if (n.isTrashed) {
      _trashMenu(n);
      return;
    }
    if (!await ensureNoteAccess(context, n)) return;
    if (!mounted) return;
    // 從搜尋結果點進來時，把關鍵字帶進去，編輯畫面會標示並捲到該位置。
    final q = _searching ? _search.text.trim() : '';
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorScreen(
          noteId: n.id,
          initialQuery: q.isEmpty ? null : q,
        ),
      ),
    );
  }

  void _showNewSheet() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_note),
              title: Text(tr('文字筆記')),
              onTap: () {
                Navigator.pop(ctx);
                _openNew(NoteType.note);
              },
            ),
            ListTile(
              leading: const Icon(Icons.key),
              title: Text(tr('帳號密碼')),
              subtitle: Text(tr('網站、帳號、密碼（預設隱藏、可一鍵複製）')),
              onTap: () {
                Navigator.pop(ctx);
                _openNew(NoteType.login);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 不用點進去，直接複製某一組帳號或密碼。
  void _quickCopy(Note n) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  n.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(ctx).textTheme.titleMedium,
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in n.credentials)
                      ListTile(
                        title: Text(
                          c.username.isEmpty ? tr('（未填帳號）') : c.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: c.username.isEmpty
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      copyWithClear(context, c.username, tr('帳號'));
                                    },
                              child: Text(tr('複製帳號')),
                            ),
                            FilledButton.tonal(
                              onPressed: c.password.isEmpty
                                  ? null
                                  : () {
                                      Navigator.pop(ctx);
                                      copyWithClear(context, c.password, tr('密碼'));
                                    },
                              child: Text(tr('複製密碼')),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _noteMenu(Note n) {
    if (n.isTrashed) {
      _trashMenu(n);
      return;
    }
    final canCopy = n.type == NoteType.login && n.credentials.isNotEmpty;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canCopy)
              ListTile(
                leading: const Icon(Icons.copy),
                title: Text(tr('快速複製帳號 / 密碼')),
                onTap: () {
                  Navigator.pop(ctx);
                  _quickCopy(n);
                },
              ),
            ListTile(
              leading: Icon(n.pinned ? Icons.push_pin_outlined : Icons.push_pin),
              title: Text(n.pinned ? tr('取消釘選') : tr('釘選')),
              onTap: () {
                Navigator.pop(ctx);
                vault.setPinned(n.id, !n.pinned);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(tr('移到資料夾')),
              onTap: () async {
                Navigator.pop(ctx);
                final r = await pickFolder(context, current: n.folderId);
                if (r != null) vault.moveToFolder(n.id, r.isEmpty ? null : r);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('移到回收桶')),
              onTap: () {
                Navigator.pop(ctx);
                _trash(n);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _trashBanner(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tr('共 $count 項。點一下可還原或永久刪除，30 天後自動永久刪除。'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(onPressed: _emptyTrash, child: Text(tr('清空'))),
        ],
      ),
    );
  }

  Future<void> _emptyTrash() async {
    final count = vault.notes.where((n) => n.isTrashed).length;
    final ok = await confirmDialog(
      context,
      title: tr('清空回收桶'),
      message: tr('共 $count 項內容會被永久刪除，無法復原。'),
      confirmText: tr('永久刪除'),
      danger: true,
    );
    if (ok) vault.emptyTrash();
  }

  void _trashMenu(Note n) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                n.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: const Icon(Icons.restore),
              title: Text(tr('還原')),
              onTap: () {
                Navigator.pop(ctx);
                vault.restore(n.id);
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(SnackBar(content: Text(tr('已還原'))));
              },
            ),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: Theme.of(ctx).colorScheme.error,
              ),
              title: Text(
                tr('永久刪除'),
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
              onTap: () async {
                Navigator.pop(ctx);
                final ok = await confirmDialog(
                  context,
                  title: tr('永久刪除'),
                  message: tr('這項內容會被永久刪除，無法復原。'),
                  confirmText: tr('永久刪除'),
                  danger: true,
                );
                if (ok) vault.deleteForever(n.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _trash(Note n) {
    vault.moveToTrash(n.id);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(tr('已移到回收桶')),
          action: SnackBarAction(
            label: tr('復原'),
            onPressed: () => vault.restore(n.id),
          ),
        ),
      );
  }

  Future<String?> _askName(String title, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: InputDecoration(hintText: tr('資料夾名稱')),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr('取消')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(tr('確定')),
          ),
        ],
      ),
    );
  }

  Future<void> _addFolder() async {
    final name = await _askName(tr('新增資料夾'));
    if (name == null || name.trim().isEmpty) return;
    final f = vault.addFolder(name);
    setState(() => _filter = 'folder:${f.id}');
  }

  void _folderMenu(Folder f) {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: Text(tr('重新命名')),
              onTap: () async {
                Navigator.pop(ctx);
                final name = await _askName(tr('重新命名'), initial: f.name);
                if (name != null && name.trim().isNotEmpty) {
                  vault.renameFolder(f.id, name);
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text(tr('刪除資料夾')),
              subtitle: Text(tr('裡面的筆記不會被刪除，會變成「不分類」')),
              onTap: () {
                Navigator.pop(ctx);
                vault.deleteFolder(f.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 「檢視」：顯示方式、欄數、排序依據與順序。
  void _showViewSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: ListenableBuilder(
            listenable: appSettings,
            builder: (ctx, _) {
              final byTitle = appSettings.sortKey == 'title';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(tr('檢視'), style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 16),
                  Text(tr('顯示方式')),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.grid_view),
                        label: Text(tr('格狀')),
                      ),
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.view_agenda_outlined),
                        label: Text(tr('列表')),
                      ),
                    ],
                    selected: {appSettings.gridView},
                    onSelectionChanged: (s) => appSettings.setGridView(s.first),
                  ),
                  if (appSettings.gridView) ...[
                    const SizedBox(height: 16),
                    Text(tr('每列顯示')),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [
                        ButtonSegment<int>(value: 2, label: Text(tr('2 欄'))),
                        ButtonSegment<int>(value: 3, label: Text(tr('3 欄'))),
                      ],
                      selected: {appSettings.gridColumns},
                      onSelectionChanged: (s) =>
                          appSettings.setGridColumns(s.first),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(tr('排序依據')),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final e in {
                        'updated': tr('最近修改'),
                        'created': tr('建立時間'),
                        'title': tr('標題'),
                        'manual': tr('自訂（長按拖曳）'),
                      }.entries)
                        ChoiceChip(
                          label: Text(e.value),
                          selected: appSettings.sortKey == e.key,
                          onSelected: (_) =>
                              appSettings.setSort(e.key, e.key == 'title'),
                        ),
                    ],
                  ),
                  if (appSettings.sortKey != 'manual') ...[
                  const SizedBox(height: 16),
                  Text(tr('順序')),
                  const SizedBox(height: 8),
                  SegmentedButton<bool>(
                    showSelectedIcon: false,
                    segments: [
                      ButtonSegment<bool>(
                        value: false,
                        label: Text(byTitle ? 'Z → A' : tr('新 → 舊')),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        label: Text(byTitle ? 'A → Z' : tr('舊 → 新')),
                      ),
                    ],
                    selected: {appSettings.sortAsc},
                    onSelectionChanged: (s) =>
                        appSettings.setSort(appSettings.sortKey, s.first),
                  ),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(tr('釘選的項目固定在最上面')),
                    value: appSettings.pinTop,
                    onChanged: appSettings.setPinTop,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _appBar() {
    if (_searching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            _searching = false;
            _search.clear();
          }),
        ),
        title: TextField(
          controller: _search,
          autofocus: true,
          enableIMEPersonalizedLearning: false,
          decoration: InputDecoration(
            hintText: tr('搜尋標題、內容、網站、帳號、標籤'),
            border: InputBorder.none,
          ),
          onChanged: (_) => setState(() {}),
        ),
        actions: [
          if (_search.text.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(_search.clear),
            ),
        ],
      );
    }
    return AppBar(
      title: Text(tr('Mido筆記')),
      actions: [
        IconButton(
          tooltip: tr('搜尋'),
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _searching = true),
        ),
        IconButton(
          tooltip: tr('檢視與排序'),
          icon: const Icon(Icons.tune),
          onPressed: _showViewSheet,
        ),
        PopupMenuButton<String>(
          onSelected: (v) {
            switch (v) {
              case 'trash':
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TrashScreen()),
                );
              case 'settings':
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
                );
              case 'lock':
                vault.lock();
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(value: 'trash', child: Text(tr('回收桶'))),
            PopupMenuItem(value: 'settings', child: Text(tr('設定'))),
            PopupMenuItem(value: 'lock', child: Text(tr('立即鎖定'))),
          ],
        ),
      ],
    );
  }

  Widget _chips() {
    final trashCount = vault.notes.where((n) => n.isTrashed).length;
    Widget chip(
      String id,
      String label, {
      IconData? icon,
      VoidCallback? onLongPress,
    }) {
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: GestureDetector(
            onLongPress: onLongPress,
            child: ChoiceChip(
            avatar: icon == null ? null : Icon(icon, size: 18),
            showCheckmark: false,
            label: Text(label),
            selected: _filter == id,
            onSelected: (_) => setState(() => _filter = id),
          ),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        children: [
          chip('all', tr('全部')),
          chip('text', tr('文字筆記'), icon: Icons.edit_note),
          chip('login', tr('帳號密碼'), icon: Icons.key),
          chip(
            'trash',
            trashCount > 0 ? tr('回收桶 ($trashCount)') : tr('回收桶'),
            icon: Icons.delete_outline,
          ),
          for (final f in vault.folders)
            chip(
              'folder:${f.id}',
              f.name,
              icon: Icons.folder_outlined,
              onLongPress: () => _folderMenu(f),
            ),
          for (final t in vault.sortedTags) chip('tag:$t', '#$t'),
          ActionChip(
            avatar: const Icon(Icons.create_new_folder_outlined, size: 18),
            label: Text(tr('新增資料夾')),
            onPressed: _addFolder,
          ),
        ],
      ),
    );
  }

  // ───────────────────────── 備份提醒 ─────────────────────────

  DateTime? _backupRef() {
    final last = appSettings.lastBackupAt;
    if (last != null) return last;
    DateTime? oldest;
    for (final n in vault.notes) {
      if (n.isTrashed) continue;
      if (oldest == null || n.createdAt.isBefore(oldest)) oldest = n.createdAt;
    }
    return oldest;
  }

  /// 需要提醒時回傳「距離上次備份幾天」，否則 null。
  int? _reminderDays() {
    if (appSettings.backupRemindDays <= 0) return null;
    final snooze = appSettings.remindSnoozedUntil;
    if (snooze != null && DateTime.now().isBefore(snooze)) return null;
    final ref = _backupRef();
    if (ref == null) return null;
    final d = DateTime.now().difference(ref).inDays;
    return d >= appSettings.backupRemindDays ? d : null;
  }

  Widget _reminderCard(int days) {
    final cs = Theme.of(context).colorScheme;
    final never = appSettings.lastBackupAt == null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Card(
        color: cs.secondaryContainer,
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                never ? tr('還沒有備份過') : tr('已經 $days 天沒有備份了'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: cs.onSecondaryContainer,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                tr('資料只存在這支手機，解除安裝 App 或換手機就會消失。建議現在匯出一份加密備份。'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSecondaryContainer,
                    ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => appSettings.snoozeBackupReminder(days: 3),
                    child: Text(tr('3 天後再提醒')),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BackupScreen(),
                      ),
                    ),
                    child: Text(tr('立即備份')),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() {
    final cs = Theme.of(context).colorScheme;
    final searching = _search.text.trim().isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? Icons.search_off
                  : (_filter == 'trash'
                      ? Icons.delete_outline
                      : Icons.sticky_note_2_outlined),
              size: 64,
              color: cs.outline,
            ),
            const SizedBox(height: 12),
            Text(
              searching
                  ? tr('找不到符合的筆記')
                  : (_filter == 'trash'
                      ? tr('回收桶是空的')
                      : tr('這裡還沒有筆記\n按右下角「新增」開始')),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.outline),
            ),
          ],
        ),
      ),
    );
  }

  Widget _grid(List<Note> notes) {
    final cols = appSettings.gridColumns;
    return GridView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: cols >= 3 ? 0.8 : 1.0,
      ),
      itemCount: notes.length,
      itemBuilder: (_, i) => _card(notes, i, true),
    );
  }

  Widget _list(List<Note> notes) {
    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
      itemCount: notes.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _card(notes, i, false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([vault, appSettings]),
      builder: (context, _) {
        if (_currentFolderId != null &&
            !vault.folders.any((f) => f.id == _currentFolderId)) {
          _filter = 'all';
        }
        if (_currentTag != null && !vault.sortedTags.contains(_currentTag)) {
          _filter = 'all';
        }
        final notes = _visible();
        final remindDays =
            (_filter == 'trash' || _searching) ? null : _reminderDays();
        return Scaffold(
          appBar: _appBar(),
          body: Column(
            children: [
              _chips(),
              if (remindDays != null) _reminderCard(remindDays),
              if (_filter == 'trash' && notes.isNotEmpty) _trashBanner(notes.length),
              Expanded(
                key: _viewKey,
                child: notes.isEmpty
                    ? _empty()
                    : (appSettings.gridView ? _grid(notes) : _list(notes)),
              ),
            ],
          ),
          floatingActionButton: _filter == 'trash'
              ? null
              : FloatingActionButton.extended(
                  onPressed: _showNewSheet,
                  icon: const Icon(Icons.add),
                  label: Text(tr('新增')),
                ),
        );
      },
    );
  }
}

/// 記事本的選項（卡片右上角「⋮」與長按共用）：key = 動作代號，value = 顯示文字。
List<MapEntry<String, String>> noteMenuItems(Note note) {
  final isLogin = note.type == NoteType.login;
  return [
    if (isLogin && note.credentials.isNotEmpty)
      MapEntry('copy', tr('快速複製帳號 / 密碼')),
    MapEntry('pin', note.pinned ? tr('取消釘選') : tr('釘選')),
    MapEntry('lock', note.locked ? tr('解除鎖定') : tr('鎖定（需輸入鎖定密碼）')),
    MapEntry('color', tr('筆記顏色')),
    MapEntry('folder', tr('移到資料夾')),
    MapEntry('duplicate', tr('複製到資料夾')),
    MapEntry('trash', tr('刪除（移到回收桶）')),
  ];
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.grid,
    required this.onTap,
    required this.onMenu,
  });

  final Note note;
  final bool grid;
  final VoidCallback onTap;
  final void Function(String action) onMenu;

  /// 預覽文字；帳密類型絕不顯示密碼，也不顯示隱藏欄位的內容。
  String get _preview {
    if (note.locked) return tr('🔒 已鎖定，點開後輸入鎖定密碼');
    if (note.type == NoteType.login) {
      return [
        for (final c in note.credentials)
          if (c.username.isNotEmpty) c.username,
        if (note.site.isNotEmpty) note.site,
        if (note.body.trim().isNotEmpty) note.body.trim(),
      ].join('\n');
    }
    return note.body.trim();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isLogin = note.type == NoteType.login;

    final header = Row(
      children: [
        if (isLogin) ...[
          Icon(Icons.key, size: 16, color: cs.primary),
          const SizedBox(width: 4),
        ],
        Expanded(
          child: Text(
            note.displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        if (note.locked) Icon(Icons.lock, size: 16, color: cs.primary),
        if (note.pinned) Icon(Icons.push_pin, size: 16, color: cs.primary),
        if (!note.isTrashed)
          PopupMenuButton<String>(
            tooltip: tr('選項'),
            padding: EdgeInsets.zero,
            iconSize: 20,
            icon: Icon(Icons.more_vert, size: 20, color: cs.onSurfaceVariant),
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onSelected: onMenu,
            itemBuilder: (_) => [
              for (final e in noteMenuItems(note))
                PopupMenuItem(value: e.key, child: Text(e.value)),
            ],
          ),
      ],
    );

    final preview = Text(
      _preview,
      maxLines: grid ? 6 : 2,
      overflow: TextOverflow.ellipsis,
      style: tt.bodyMedium,
    );

    final tags = note.tags.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              note.tags.map((t) => '#$t').join(' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tt.labelSmall?.copyWith(color: cs.primary),
            ),
          );

    final footer = Row(
      children: [
        Text(
          note.isTrashed
              ? tr('刪除於 ${fmtDate(note.deletedAt!)}')
              : fmtDate(note.updatedAt),
          style: tt.labelSmall,
        ),
        if (isLogin && note.credentials.length > 1) ...[
          const SizedBox(width: 8),
          Text(
            tr('${note.credentials.length} 組帳號'),
            style: tt.labelSmall?.copyWith(color: cs.primary),
          ),
        ],
        const Spacer(),
        if (note.imageIds.isNotEmpty)
          Icon(Icons.image_outlined, size: 14, color: cs.outline),
      ],
    );

    final accent = noteColorOf(note.color);
    return Card(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: accent == null
          ? cs.surfaceContainerLow
          : Color.alphaBlend(accent.withValues(alpha: 0.16), cs.surfaceContainerLow),
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: accent == null
              ? null
              : BoxDecoration(
                  border: Border(left: BorderSide(color: accent, width: 5)),
                ),
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: grid ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 6),
              if (grid) Expanded(child: preview) else preview,
              const SizedBox(height: 6),
              if (tags != null) tags,
              footer,
            ],
          ),
        ),
      ),
    );
  }
}
