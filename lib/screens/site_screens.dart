import 'package:flutter/material.dart';

import '../data/models.dart';
import '../services/audio_center.dart';
import '../services/site_data.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/source_book.dart' show openBook;
import 'audio_library.dart';

const _by = 'الشيخ سلمان بن صالح العماد';

/// Plays [list] from [at] in the app's own player, one after the other.
void playTracks(BuildContext context, List<SiteTrack> list, int at) {
  AudioCenter.instance.playQueue([for (final t in list) AudioItem(t.title, t.url, by: _by)], at);
  PlayerSheet.open(context);
}

/// One list of recordings (a section, or a lesson series), with a search box.
class TrackListScreen extends StatefulWidget {
  final String title;
  final List<SiteTrack> items;
  const TrackListScreen({super.key, required this.title, required this.items});

  @override
  State<TrackListScreen> createState() => _TrackListScreenState();
}

class _TrackListScreenState extends State<TrackListScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final q = stripMarks(_q.trim());
    final list = q.isEmpty ? widget.items : widget.items.where((t) => stripMarks(t.title).contains(q)).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Column(children: [
        if (widget.items.length > 8)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              onChanged: (v) => setState(() => _q = v),
              decoration: InputDecoration(
                hintText: 'ابحث في ${widget.items.length} تسجيلاً',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        if (list.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text('تشغيل الكل (${list.length})'),
                onPressed: () => playTracks(context, list, 0),
              ),
            ),
          ),
        Expanded(
          child: list.isEmpty
              ? const EmptyState(icon: Icons.headphones_outlined, text: 'لا نتائج')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 120),
                  itemCount: list.length,
                  itemBuilder: (context, i) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: kGold.withValues(alpha: .18),
                        child: Text('${i + 1}',
                            style: const TextStyle(color: kGoldChip, fontWeight: FontWeight.bold, fontSize: 13)),
                      ),
                      title: Text(list[i].title,
                          maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
                      trailing: const Icon(Icons.play_circle_outline),
                      onTap: () => playTracks(context, list, i),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }
}

/// Arabic text without its marks, so a search finds a vowelled title.
String stripMarks(String s) => s
    .replaceAll(RegExp('[ً-ْٰـ]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll('ة', 'ه')
    .replaceAll('ى', 'ي');

class _ListCard extends StatelessWidget {
  final SiteList list;
  final IconData icon;
  const _ListCard({required this.list, required this.icon});

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 10),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: CircleAvatar(
              radius: 24, backgroundColor: kGold.withValues(alpha: .18), child: Icon(icon, color: kGoldChip)),
          title: Text(list.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: kUiFont, fontWeight: FontWeight.bold, fontSize: 15.5, height: 1.5)),
          subtitle: Text('${list.items.length} تسجيلاً'),
          trailing: const Icon(Icons.chevron_left),
          onTap: () => Navigator.of(context)
              .push(MaterialPageRoute(builder: (_) => TrackListScreen(title: list.name, items: list.items))),
        ),
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
          final channel = IconButton(
            tooltip: 'تسجيلات القناة',
            icon: const Icon(Icons.send_rounded),
            onPressed: () =>
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AudioLibraryScreen())),
          );
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

/// The lesson series of the site, each field of knowledge with its series.
class SiteLessonsView extends StatelessWidget {
  const SiteLessonsView({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SiteData.instance,
        builder: (context, _) {
          final fields = SiteData.instance.lessons;
          if (fields.isEmpty) {
            return const EmptyState(icon: Icons.school_outlined, text: 'تُحمَّل قائمة الدروس…');
          }
          return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 120), children: [
            for (final f in fields)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  shape: const Border(),
                  leading: CircleAvatar(
                      backgroundColor: kGold.withValues(alpha: .18),
                      child: const Icon(Icons.school_rounded, color: kGoldChip)),
                  title: Text(f.name,
                      style: const TextStyle(fontFamily: kUiFont, fontWeight: FontWeight.bold, fontSize: 16.5)),
                  subtitle: Text('${f.lists.length} سلسلة · ${f.count} درساً'),
                  children: [
                    for (final c in f.lists)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.playlist_play_rounded),
                        title: Text(c.name,
                            maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, height: 1.5)),
                        trailing: Text('${c.items.length}', style: TextStyle(color: Pal.muted(context))),
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => TrackListScreen(title: c.name, items: c.items))),
                      ),
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
