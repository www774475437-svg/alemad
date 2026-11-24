import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/audio_center.dart';
import '../services/books_store.dart';
import '../services/site_data.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/source_book.dart' show openBook;
import 'audio_library.dart';

const _by = 'الشيخ سلمان بن صالح العماد';

AudioItem _item(SiteList list, SiteTrack t) => AudioItem(t.title, t.url, by: _by, ref: '${list.key}/${t.id}');

/// Plays [tracks] of [list] from [at] in the app's own player, one after the other.
void playTracks(BuildContext context, SiteList list, List<SiteTrack> tracks, int at, {int? fromSecond}) {
  final items = [for (final t in tracks) _item(list, t)];
  if (fromSecond != null) {
    AudioCenter.instance.playQueue(items, at).then((_) => AudioCenter.instance.playAt(items[at], fromSecond));
  } else {
    AudioCenter.instance.playQueue(items, at);
  }
  PlayerSheet.open(context);
}

String _size(int bytes) =>
    bytes >= 1024 * 1024 ? '${(bytes / 1024 / 1024).toStringAsFixed(1)} م.ب' : '${(bytes / 1024).round()} ك.ب';

/// One list of recordings (a section, or a lesson series): read when opened,
/// with a search box, what was heard of it, and «download all».
class TrackListScreen extends StatefulWidget {
  final SiteList list;

  /// Opens playing this recording (a shared moment), from [startSecond].
  final int? startId, startSecond;
  const TrackListScreen({super.key, required this.list, this.startId, this.startSecond});

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  List<SiteTrack>? _all;
  Set<String> _heard = {};
  String _q = '';
  int _dlDone = -1, _dlTotal = 0; // «download all» progress (-1 = idle)
  bool _stop = false;

  @override
  void initState() {
    super.initState();
    AudioCenter.instance.addListener(_refreshHeard);
    _load();
  }

  @override
  void dispose() {
    AudioCenter.instance.removeListener(_refreshHeard);
    _stop = true;
    super.dispose();
  }

  void _refreshHeard() {
    AudioCenter.instance.heard().then((h) {
      if (mounted && h.length != _heard.length) setState(() => _heard = {...h});
    });
  }

  Future<void> _load() async {
    final list = await SiteData.instance.tracks(widget.list.key);
    final heard = await AudioCenter.instance.heard();
    if (!mounted) return;
    setState(() {
      _all = list;
      _heard = {...heard};
    });
    final id = widget.startId;
    if (id != null) {
      final at = list.indexWhere((t) => t.id == id);
      if (at >= 0) playTracks(context, widget.list, list, at, fromSecond: widget.startSecond);
    }
  }

  Future<void> _downloadAll(List<SiteTrack> list) async {
    final a = AudioCenter.instance;
    setState(() {
      _dlDone = 0;
      _dlTotal = list.length;
      _stop = false;
    });
    var failed = 0;
    for (final t in list) {
      if (_stop || !mounted) break;
      final it = _item(widget.list, t);
      if (!await a.isDownloaded(it)) {
        if (await a.download(it) != null) failed++;
      }
      if (mounted) setState(() => _dlDone++);
    }
    if (!mounted) return;
    setState(() => _dlDone = -1);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(failed == 0 ? 'نُزّلت السلسلة، وتُسمع الآن بلا إنترنت' : 'تعذّر تنزيل $failed، أعد المحاولة لاحقاً')));
  }

  @override
  Widget build(BuildContext context) {
    final all = _all;
    final q = SiteData.norm(_q.trim());
    final list = all == null
        ? const <SiteTrack>[]
        : q.isEmpty
            ? all
            : all.where((t) => SiteData.norm(t.title).contains(q)).toList();
    final done = all == null ? 0 : all.where((t) => _heard.contains(_item(widget.list, t).key)).length;
    return Scaffold(
      appBar: AppBar(title: Text(widget.list.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: all == null
          ? const Center(child: CircularProgressIndicator())
          : all.isEmpty
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const EmptyState(
                      icon: Icons.wifi_off_rounded, text: 'تعذّر تحميل القائمة.\nتأكد من اتصالك بالإنترنت ثم أعد المحاولة.'),
                  const SizedBox(height: 12),
                  FilledButton(
                      onPressed: () {
                        setState(() => _all = null);
                        _load();
                      },
                      child: const Text('إعادة المحاولة')),
                ])
              : Column(children: [
                  // What was heard of this list.
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Row(children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: LinearProgressIndicator(
                              value: all.isEmpty ? 0 : done / all.length,
                              minHeight: 8,
                              color: kGold,
                              backgroundColor: kGold.withValues(alpha: .18)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text('سمعت $done من ${all.length}', style: TextStyle(color: Pal.muted(context), fontSize: 13)),
                    ]),
                  ),
                  if (all.length > 8)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                      child: TextField(
                        onChanged: (v) => setState(() => _q = v),
                        decoration: InputDecoration(
                          hintText: 'ابحث في ${all.length} تسجيلاً',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    child: Row(children: [
                      Expanded(
                        child: FilledButton.icon(
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: Text('تشغيل الكل (${list.length})'),
                          onPressed: list.isEmpty ? null : () => playTracks(context, widget.list, list, 0),
                        ),
                      ),
                      if (!kIsWeb) ...[
                        const SizedBox(width: 8),
                        _dlDone >= 0
                            ? OutlinedButton.icon(
                                icon: const SizedBox(
                                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                label: Text('$_dlDone/$_dlTotal · إيقاف'),
                                onPressed: () => _stop = true,
                              )
                            : OutlinedButton.icon(
                                icon: const Icon(Icons.download_rounded),
                                label: const Text('تنزيل الكل'),
                                onPressed: () => _downloadAll(all),
                              ),
                      ],
                    ]),
                  ),
                  Expanded(
                    child: list.isEmpty
                        ? const EmptyState(icon: Icons.headphones_outlined, text: 'لا نتائج')
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 120),
                            itemCount: list.length,
                            itemBuilder: (context, i) {
                              final key = _item(widget.list, list[i]).key;
                              final heard = _heard.contains(key);
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: heard ? const Color(0xFF2E7D32) : kGold.withValues(alpha: .18),
                                    child: heard
                                        ? const Icon(Icons.check, color: Colors.white, size: 20)
                                        : Text('${i + 1}',
                                            style: const TextStyle(
                                                color: kGoldChip, fontWeight: FontWeight.bold, fontSize: 13)),
                                  ),
                                  title: Text(list[i].title,
                                      maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
                                  subtitle: heard ? const Text('تمّ الاستماع') : null,
                                  trailing: IconButton(
                                    tooltip: heard ? 'إزالة علامة «تمّ»' : 'علّمه «تمّ»',
                                    icon: Icon(heard ? Icons.check_circle : Icons.check_circle_outline,
                                        color: heard ? const Color(0xFF2E7D32) : null),
                                    onPressed: () async {
                                      await AudioCenter.instance.setHeard(key, !heard);
                                      _refreshHeard();
                                    },
                                  ),
                                  onTap: () => playTracks(context, widget.list, list, i),
                                ),
                              );
                            },
                          ),
                  ),
                ]),
    );
  }
}

/// A list you browse in place: press it and its recordings open under it,
/// press one and it plays. No page in between.
class _ListCard extends StatefulWidget {
  final SiteList list;
  final IconData icon;
  const _ListCard({super.key, required this.list, required this.icon});

  @override
  State<_ListCard> createState() => _ListCardState();
}

class _ListCardState extends State<_ListCard> {
  static const _first = 25;
  bool _open = false;
  List<SiteTrack>? _tracks;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open && _tracks == null) {
      SiteData.instance.tracks(widget.list.key).then((t) {
        if (mounted) setState(() => _tracks = t);
      });
    }
  }

  void _whole() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TrackListScreen(list: widget.list)));

  @override
  Widget build(BuildContext context) {
    final list = widget.list, t = _tracks;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: CircleAvatar(
              radius: 24, backgroundColor: kGold.withValues(alpha: .18), child: Icon(widget.icon, color: kGoldChip)),
          title: Text(list.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: kUiFont, fontWeight: FontWeight.bold, fontSize: 15.5, height: 1.5)),
          subtitle: Text(widget.icon == Icons.school_rounded ? '${list.count} درساً' : '${list.count} تسجيلاً'),
          trailing: Icon(_open ? Icons.expand_less : Icons.expand_more),
          onTap: _toggle,
        ),
        if (_open && t == null)
          const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator())),
        if (_open && t != null && t.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('تعذّر التحميل، تأكد من الإنترنت ثم أعد المحاولة.')),
        if (_open && t != null && t.isNotEmpty) ...[
          const Divider(height: 1),
          for (var i = 0; i < t.length && i < _first; i++)
            ListTile(
              dense: true,
              leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: kGold.withValues(alpha: .15),
                  child: Text('${i + 1}', style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold))),
              title: Text(t[i].title,
                  maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14.5, height: 1.5)),
              trailing: const Icon(Icons.play_circle_outline_rounded),
              onTap: () => playTracks(context, list, t, i),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => playTracks(context, list, t, 0),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('تشغيل الكل'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _whole,
                  icon: const Icon(Icons.list_rounded),
                  label: Text(t.length > _first ? 'الكل (${t.length})' : 'بحث وتنزيل'),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// One search in everything: recordings and lessons, books, and the written
/// answers and articles.
class EverythingSearchScreen extends StatefulWidget {
  const EverythingSearchScreen({super.key});

  @override
  State<EverythingSearchScreen> createState() => _EverythingSearchScreenState();
}

class _EverythingSearchScreenState extends State<EverythingSearchScreen> {
  String _q = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    SiteData.instance.loadTitles().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim();
    final nq = SiteData.norm(q);
    final hits = q.length < 2 ? const <SiteHit>[] : SiteData.instance.search(q);
    final books = q.length < 2
        ? const <Book>[]
        : SiteData.instance.books.where((b) => SiteData.norm(b.title).contains(nq)).take(12).toList();
    final texts = q.length < 2 ? const <Fatwa>[] : Repository.instance.search(q).take(15).toList();
    Widget head(String t, int n) => Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Text('$t ($n)', style: const TextStyle(fontFamily: kUiFont, fontWeight: FontWeight.bold, fontSize: 16)),
        );
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _q = v),
          style: TextStyle(color: Theme.of(context).appBarTheme.foregroundColor),
          cursorColor: kGold,
          decoration: InputDecoration(
            hintText: 'ابحث في الصوتيات والدروس والكتب والمقالات',
            hintStyle: TextStyle(color: (Theme.of(context).appBarTheme.foregroundColor ?? Colors.white).withValues(alpha: .6)),
            border: InputBorder.none,
          ),
        ),
      ),
      body: q.length < 2
          ? const EmptyState(icon: Icons.search, text: 'اكتب كلمة أو أكثر\nيبحث في عناوين الصوتيات والدروس، وفي الكتب، وفي المقالات والأجوبة')
          : ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 120), children: [
              if (!_ready) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
              if (hits.isNotEmpty) head('الصوتيات والدروس', hits.length),
              for (final h in hits)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.play_circle_outline, color: kGoldChip),
                    title: Text(h.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.5)),
                    subtitle: Text(h.list.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () async {
                      final tracks = await SiteData.instance.tracks(h.list.key);
                      if (!context.mounted || h.at >= tracks.length) return;
                      playTracks(context, h.list, tracks, h.at);
                    },
                  ),
                ),
              if (books.isNotEmpty) head('الكتب', books.length),
              for (final b in books)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.menu_book_rounded, color: kGoldChip),
                    title: Text(b.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.5)),
                    onTap: () => openBook(context, b),
                  ),
                ),
              if (texts.isNotEmpty) head('المقالات والأجوبة', texts.length),
              for (final f in texts)
                Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.article_outlined, color: kGoldChip),
                    title: Text(f.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.5)),
                    onTap: () => openFatwa(context, f),
                  ),
                ),
              if (_ready && hits.isEmpty && books.isEmpty && texts.isEmpty)
                const Padding(padding: EdgeInsets.only(top: 60), child: EmptyState(icon: Icons.search_off, text: 'لا نتائج')),
            ]),
    );
  }
}

/// «المساحة»: what was downloaded to the phone (recordings and books), each
/// with its size, to delete and free space.
class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
  List<(String, String, int)>? _audio;
  List<(String, int)> _books = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (kIsWeb) return;
    final a = [...await AudioCenter.instance.downloads()];
    final b = [...await BooksStore.downloaded()];
    if (mounted) {
      setState(() {
        _audio = a..sort((x, y) => y.$3.compareTo(x.$3));
        _books = b..sort((x, y) => y.$2.compareTo(x.$2));
      });
    }
  }

  String _bookTitle(String id) {
    for (final b in Repository.instance.books) {
      if (b.id == id) return b.title;
    }
    return 'كتاب محفوظ';
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('حذف كل ما نُزّل؟'),
        content: const Text('تُحذف الصوتيات والكتب المنزّلة من هاتفك، وتبقى في التطبيق لتسمعها وتقرأها بالإنترنت أو تنزّلها مرة أخرى.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('حذف الكل')),
        ],
      ),
    );
    if (ok != true) return;
    for (final a in _audio ?? const <(String, String, int)>[]) {
      await AudioCenter.instance.removeDownloadKey(a.$1);
    }
    for (final b in _books) {
      await BooksStore.deleteId(b.$1);
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final audio = _audio;
    final total = (audio ?? const []).fold<int>(0, (a, e) => a + e.$3) + _books.fold<int>(0, (a, e) => a + e.$2);
    return Scaffold(
      appBar: AppBar(title: const Text('المساحة')),
      body: kIsWeb
          ? const EmptyState(icon: Icons.sd_storage_outlined, text: 'التنزيل للاستماع بلا إنترنت في تطبيق الجوال.\nفي الموقع لا يُحفظ شيء على جهازك.')
          : audio == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 120), children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('المحفوظ على هاتفك: ${_size(total)}',
                            style: const TextStyle(fontFamily: kUiFont, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text('${audio.length} تسجيلاً · ${_books.length} كتاباً', style: TextStyle(color: Pal.muted(context))),
                        if (total > 0) ...[
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                              icon: const Icon(Icons.delete_sweep_outlined), label: const Text('حذف الكل'), onPressed: _clear),
                        ],
                      ]),
                    ),
                  ),
                  if (total == 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 50),
                      child: EmptyState(
                          icon: Icons.sd_storage_outlined,
                          text: 'لم تنزّل شيئاً بعد.\nالتطبيق لا يحفظ على هاتفك إلا ما تنزّله أنت.'),
                    ),
                  if (audio.isNotEmpty)
                    const Padding(
                        padding: EdgeInsets.fromLTRB(4, 14, 4, 6),
                        child: Text('الصوتيات', style: TextStyle(fontFamily: kUiFont, fontWeight: FontWeight.bold, fontSize: 16))),
                  for (final a in audio)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        leading: const Icon(Icons.headphones_rounded, color: kGoldChip),
                        title: Text(a.$2, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
                        subtitle: Text(_size(a.$3)),
                        trailing: IconButton(
                          tooltip: 'حذف',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await AudioCenter.instance.removeDownloadKey(a.$1);
                            _load();
                          },
                        ),
                      ),
                    ),
                  if (_books.isNotEmpty)
                    const Padding(
                        padding: EdgeInsets.fromLTRB(4, 14, 4, 6),
                        child: Text('الكتب', style: TextStyle(fontFamily: kUiFont, fontWeight: FontWeight.bold, fontSize: 16))),
                  for (final b in _books)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        leading: const Icon(Icons.menu_book_rounded, color: kGoldChip),
                        title: Text(_bookTitle(b.$1), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
                        subtitle: Text(_size(b.$2)),
                        trailing: IconButton(
                          tooltip: 'حذف',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await BooksStore.deleteId(b.$1);
                            _load();
                          },
                        ),
                      ),
                    ),
                ]),
    );
  }
}

/// «أكمل الاستماع»: back to the recording one stopped at, at the same minute.
class ContinueListeningCard extends StatefulWidget {
  const ContinueListeningCard({super.key});

  @override
  State<ContinueListeningCard> createState() => _ContinueListeningCardState();
}

class _ContinueListeningCardState extends State<ContinueListeningCard> {
  (AudioItem, int, int)? _last;

  @override
  void initState() {
    super.initState();
    AudioCenter.lastPlayed().then((v) {
      if (mounted) setState(() => _last = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = _last;
    if (l == null) return const SizedBox.shrink();
    final at = PlayerSheet.fmt(Duration(seconds: l.$2));
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: const CircleAvatar(backgroundColor: kGold, child: Icon(Icons.play_arrow_rounded, color: Colors.black)),
          title: const Text('أكمل الاستماع', style: TextStyle(fontFamily: kUiFont, fontWeight: FontWeight.bold)),
          subtitle: Text('${l.$1.title}\nتوقفت عند $at', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
          isThreeLine: true,
          onTap: () {
            AudioCenter.instance.play(l.$1);
            PlayerSheet.open(context);
          },
        ),
      ),
    );
  }
}

/// On Fridays, the newest sermon sits at the top of home.
class FridayKhutbaCard extends StatelessWidget {
  const FridayKhutbaCard({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SiteData.instance,
        builder: (context, _) {
          final k = SiteData.instance.khutba;
          final list = SiteData.instance.listOf('s6');
          if (k == null || list == null || DateTime.now().weekday != DateTime.friday) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Material(
              color: const Color(0xFF1E3A5F),
              borderRadius: BorderRadius.circular(22),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => playTracks(context, list, [k], 0),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    const Icon(Icons.mosque_rounded, color: kGold, size: 36),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('خطبة الجمعة', style: TextStyle(color: kGold, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(k.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: kUiFont, color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16.5, height: 1.5)),
                      ]),
                    ),
                    const Icon(Icons.play_circle_fill_rounded, color: kGold, size: 38),
                  ]),
                ),
              ),
            ),
          );
        },
      );
}

/// «الصوتيات»: the sheikh's recitations, sermons, lectures and refutations,
/// from his official site, played inside the app.
class SiteAudioTab extends StatelessWidget {
  const SiteAudioTab({super.key});

  static IconData _icon(String group) => group.contains('تلاو')
      ? Icons.menu_book_rounded
      : group.contains('رد')
          ? Icons.shield_outlined
          : Icons.mic_rounded;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SiteData.instance,
        builder: (context, _) {
          final groups = SiteData.instance.audio;
          final channel = Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'بحث',
              icon: const Icon(Icons.search_rounded),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EverythingSearchScreen())),
            ),
            IconButton(
              tooltip: 'المساحة',
              icon: const Icon(Icons.sd_storage_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const StorageScreen())),
            ),
            IconButton(
              tooltip: 'تسجيلات القناة',
              icon: const Icon(Icons.send_rounded),
              onPressed: () =>
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AudioLibraryScreen())),
            ),
          ]);
          if (groups.isEmpty) {
            return Scaffold(
              appBar: AppBar(title: const Text('الصوتيات'), actions: [channel]),
              body: const EmptyState(
                  icon: Icons.headphones_outlined, text: 'تُحمَّل قائمة الصوتيات…\nتأكد من اتصالك بالإنترنت ثم عُد بعد قليل.'),
            );
          }
          return DefaultTabController(
            length: groups.length,
            child: Scaffold(
              appBar: AppBar(
                title: Text('الصوتيات (${SiteData.instance.audioCount})'),
                actions: [channel],
                bottom: TabBar(isScrollable: groups.length > 3, tabs: [for (final g in groups) Tab(text: g.name)]),
              ),
              body: TabBarView(children: [
                for (final g in groups)
                  ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 120), children: [
                    for (final l in g.lists) _ListCard(list: l, icon: _icon(g.name)),
                  ]),
              ]),
            ),
          );
        },
      );
}

/// The lessons of the site: the fields of knowledge as chips on top, and
/// under them the books of the chosen field, each opening in place.
class SiteLessonsView extends StatefulWidget {
  const SiteLessonsView({super.key});

  @override
  State<SiteLessonsView> createState() => _SiteLessonsViewState();
}

class _SiteLessonsViewState extends State<SiteLessonsView> {
  int _at = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SiteData.instance,
        builder: (context, _) {
          final fields = SiteData.instance.lessons;
          if (fields.isEmpty) {
            return const EmptyState(icon: Icons.school_outlined, text: 'تُحمَّل قائمة الدروس…');
          }
          final at = _at < fields.length ? _at : 0;
          final f = fields[at];
          return Column(children: [
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                itemCount: fields.length,
                separatorBuilder: (context, i) => const SizedBox(width: 8),
                itemBuilder: (context, i) => ChoiceChip(
                  label: Text('${fields[i].name} (${fields[i].lists.length})',
                      style: const TextStyle(fontFamily: kUiFont, fontWeight: FontWeight.bold)),
                  selected: i == at,
                  onSelected: (_) => setState(() => _at = i),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                key: ValueKey(f.name),
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 120),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    child: Text('${f.lists.length} شرحاً · ${f.count} درساً — اضغط الشرح لتظهر دروسه',
                        style: TextStyle(color: Pal.muted(context), fontSize: 12.5)),
                  ),
                  for (final c in f.lists) _ListCard(key: ValueKey(c.key), list: c, icon: Icons.school_rounded),
                ],
              ),
            ),
          ]);
        },
      );
}

const _levelNames = ['', 'الأول', 'الثاني', 'الثالث', 'الرابع', 'الخامس', 'السادس', 'السابع'];

/// «المتون العلمية»: «مفتاح العلوم» with its seven levels, as the sheikh
/// ordered them.
class MutunTab extends StatelessWidget {
  const MutunTab({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('المتون العلمية')),
        body: ListenableBuilder(
          listenable: SiteData.instance,
          builder: (context, _) {
            final levels = SiteData.instance.levels;
            final whole = SiteData.instance.wholeSet;
            if (levels.isEmpty && whole == null) {
              return const EmptyState(icon: Icons.auto_stories_outlined, text: 'تُحمَّل المتون…');
            }
            return ListView(padding: const EdgeInsets.fromLTRB(14, 14, 14, 120), children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF2A0C12), Color(0xFF8C2F39), Color(0xFF3A1018)]),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('مفتاح العلوم',
                      style: TextStyle(fontFamily: kUiFont, color: kGold, fontSize: 24, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('سلّم المتون الذي رتّبه الشيخ لطالب العلم في سبعة مستويات، يُحفظ ويُدرس مستوى بعد مستوى.',
                      style: TextStyle(color: Colors.white, height: 1.8, fontSize: 14.5)),
                  if (whole != null) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: kGold, foregroundColor: Colors.black),
                      icon: const Icon(Icons.menu_book_rounded),
                      label: const Text('المجموع كاملاً (٣٠ متناً)', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: () => openBook(context, whole),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 14),
              for (final b in levels) _LevelCard(book: b),
            ]);
          },
        ),
      );
}

class _LevelCard extends StatelessWidget {
  final Book book;
  const _LevelCard({required this.book});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => openBook(context, book),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: kGold.withValues(alpha: .16),
                    border: Border.all(color: kGold, width: 1.6)),
                child: Text('${book.level}',
                    style: const TextStyle(fontFamily: kUiFont, fontSize: 22, fontWeight: FontWeight.bold, color: kGoldChip)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('المستوى ${_levelNames[book.level.clamp(0, 7)]}',
                      style: const TextStyle(fontFamily: kUiFont, fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('متون هذا المستوى من «مفتاح العلوم»', style: TextStyle(color: Pal.muted(context), fontSize: 13)),
                ]),
              ),
              const Icon(Icons.chevron_left),
            ]),
          ),
        ),
      );
}


/// Opens a shared moment: waits for the index, then the list plays it.
class ClipOpener extends StatefulWidget {
  final String listKey;
  final int id, second;
  const ClipOpener({super.key, required this.listKey, required this.id, required this.second});

  @override
  State<ClipOpener> createState() => _ClipOpenerState();
}

class _ClipOpenerState extends State<ClipOpener> {
  @override
  void initState() {
    super.initState();
    SiteData.instance.load();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SiteData.instance,
        builder: (context, _) {
          final list = SiteData.instance.listOf(widget.listKey);
          if (list == null) {
            return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
          }
          return TrackListScreen(list: list, startId: widget.id, startSecond: widget.second);
        },
      );
}
