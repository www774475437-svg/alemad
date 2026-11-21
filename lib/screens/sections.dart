import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/cloud.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'audio_library.dart';
import 'books_tab.dart';
import 'chapter_screen.dart';
import 'content_screens.dart';
import 'favorites_tab.dart';
import 'my_benefits.dart';

/// Whether a title is a Friday sermon.
bool isKhutba(String title) => title.contains('خطبة') || title.contains('خطب ') || title.contains('الخطبة');

/// «الدروس»: the learning series with their progress, the videos, and the
/// Friday sermons on their own.
class LessonsTab extends StatelessWidget {
  const LessonsTab({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('الدروس'),
            bottom: const TabBar(tabs: [Tab(text: 'السلاسل العلمية'), Tab(text: 'المرئيات'), Tab(text: 'خطب الجمعة')]),
          ),
          body: const TabBarView(children: [_SeriesList(), _VideoList(), _KhutbaList()]),
        ),
      );
}

class _SeriesList extends StatelessWidget {
  const _SeriesList();

  @override
  Widget build(BuildContext context) {
    final cloud = Cloud.instance, repo = Repository.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([cloud, repo]),
      builder: (context, _) {
        final list = cloud.series;
        if (list.isEmpty) {
          return const EmptyState(
              icon: Icons.school_outlined, text: 'لم تُضف سلاسل بعد.\nتظهر هنا سلاسل الشيخ العلمية مرتّبة، مع ما أنجزته من كل سلسلة.');
        }
        final read = repo.everRead;
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final s = list[i];
            final total = s.ids.where((id) => repo.findById(id) != null).length;
            final done = s.ids.where(read.contains).length;
            final part = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SeriesScreen(seriesId: s.id))),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    SizedBox(
                      width: 54,
                      height: 54,
                      child: Stack(alignment: Alignment.center, children: [
                        CircularProgressIndicator(
                            value: part, strokeWidth: 5, color: kGold, backgroundColor: kGold.withValues(alpha: .18)),
                        Text('${(part * 100).round()}٪', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold)),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: kUiFont, fontSize: 16.5, fontWeight: FontWeight.bold, height: 1.5)),
                        const SizedBox(height: 4),
                        Text(done >= total && total > 0 ? 'أتممت السلسلة ($total)' : 'أنجزت $done من $total',
                            style: TextStyle(color: Pal.muted(context), fontSize: 13)),
                      ]),
                    ),
                    const Icon(Icons.chevron_left),
                  ]),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _VideoList extends StatelessWidget {
  const _VideoList();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Repository.instance,
        builder: (context, _) {
          final list = Repository.instance.videos.where((v) => !isKhutba(v.title)).toList();
          if (list.isEmpty) return const EmptyState(icon: Icons.play_circle_outline, text: 'لا مقاطع بعد');
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, i) => VideoCard(video: list[i]),
          );
        },
      );
}

/// Friday sermons, seen and heard, gathered in one place.
class _KhutbaList extends StatefulWidget {
  const _KhutbaList();

  @override
  State<_KhutbaList> createState() => _KhutbaListState();
}

class _KhutbaListState extends State<_KhutbaList> {
  List<Recording> _recs = [];

  @override
  void initState() {
    super.initState();
    Recordings.load().then((l) {
      if (mounted) setState(() => _recs = l.where((r) => isKhutba(r.title)).toList());
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Repository.instance,
        builder: (context, _) {
          final videos = Repository.instance.videos.where((v) => isKhutba(v.title)).toList();
          if (videos.isEmpty && _recs.isEmpty) {
            return const EmptyState(
                icon: Icons.mosque_outlined, text: 'تظهر هنا خطب الجمعة للشيخ، المرئية والصوتية، حين تُنشر في قناته.');
          }
          return ListView(padding: const EdgeInsets.all(12), children: [
            for (final v in videos) Padding(padding: const EdgeInsets.only(bottom: 12), child: VideoCard(video: v)),
            for (final r in _recs)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: kGold.withValues(alpha: .18),
                    child: const Icon(Icons.play_arrow, color: kGoldChip),
                  ),
                  title: Text(r.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(height: 1.5)),
                  subtitle: Text([if (r.dur.isNotEmpty) '⏱ ${r.dur}', r.date].join('  ·  ')),
                  onTap: () => openRecording(context, r, list: _recs),
                ),
              ),
          ]);
        },
      );
}

/// «المكتبة»: the books, what the reader saved, and his own notebook.
class LibraryTab extends StatelessWidget {
  const LibraryTab({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('المكتبة')),
      body: ListenableBuilder(
        listenable: repo,
        builder: (context, _) => ListView(padding: const EdgeInsets.all(14), children: [
          _LibraryCard(
            icon: Icons.menu_book_rounded,
            title: 'كتب الشيخ',
            subtitle: repo.books.isEmpty ? 'تُضاف قريباً' : '${repo.books.length} كتاباً، تُقرأ داخل التطبيق',
            colors: const [Color(0xFF5E1B24), Color(0xFF8C2F39)],
            page: const BooksTab(),
          ),
          _LibraryCard(
            icon: Icons.bookmark_rounded,
            title: 'المحفوظات',
            subtitle: 'ما حفظته، وما أجّلته للقراءة، ومجلداتك',
            colors: const [Color(0xFF1E3A5F), Color(0xFF2F5C8F)],
            page: const FavoritesTab(),
          ),
          _LibraryCard(
            icon: Icons.edit_note_rounded,
            title: 'دفتري',
            subtitle: repo.myBenefits.isEmpty ? 'فوائد تقتبسها أو تكتبها بنفسك' : '${repo.myBenefits.length} فائدة في دفترك',
            colors: const [Color(0xFF7A5A22), Color(0xFFC9A54C)],
            page: const MyBenefitsScreen(),
          ),
        ]),
      ),
    );
  }
}

class _LibraryCard extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final List<Color> colors;
  final Widget page;
  const _LibraryCard(
      {required this.icon, required this.title, required this.subtitle, required this.colors, required this.page});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Material(
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          elevation: 2,
          child: Ink(
            decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topRight, end: Alignment.bottomLeft, colors: colors)),
            child: InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
                child: Row(children: [
                  Icon(icon, color: Colors.white, size: 40),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title,
                          style: const TextStyle(
                              fontFamily: kUiFont, color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: const TextStyle(color: Colors.white70, fontSize: 13.5, height: 1.5)),
                    ]),
                  ),
                  const Icon(Icons.chevron_left, color: Colors.white),
                ]),
              ),
            ),
          ),
        ),
      );
}

/// The big card at the top of home: the sheikh's newest lesson.
class LatestLessonCard extends StatelessWidget {
  final List<Recording> recordings;
  const LatestLessonCard({super.key, required this.recordings});

  @override
  Widget build(BuildContext context) {
    final videos = Repository.instance.videos;
    final Video? v = videos.isEmpty ? null : videos.first;
    final Recording? r = v == null && recordings.isNotEmpty ? recordings.first : null;
    if (v == null && r == null) return const SizedBox.shrink();
    final title = v?.title ?? r!.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        elevation: 3,
        child: Ink(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF2A0C12), Color(0xFF8C2F39), Color(0xFF3A1018)],
            ),
          ),
          child: InkWell(
            onTap: () {
              if (v != null) {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => VideoPlayerScreen(video: v)));
              } else {
                openRecording(context, r!, list: recordings);
              }
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: kGold.withValues(alpha: .18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: kGold.withValues(alpha: .7))),
                    child: Text(v != null ? 'آخر درس مرئي' : 'آخر درس صوتي',
                        style: const TextStyle(color: kGold, fontSize: 12.5, fontWeight: FontWeight.bold)),
                  ),
                ]),
                const SizedBox(height: 12),
                Text(title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: kUiFont, color: Colors.white, fontSize: 19, height: 1.6, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(color: kGold, shape: BoxShape.circle),
                    child: Icon(v != null ? Icons.play_arrow_rounded : Icons.headphones_rounded, color: Colors.black, size: 26),
                  ),
                  const SizedBox(width: 10),
                  Text(v != null ? 'شاهد الآن' : 'استمع الآن',
                      style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                ]),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chapters as a grid of squares.
class ChapterGrid extends StatelessWidget {
  const ChapterGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final repo = Repository.instance;
    final chapters = repo.chapters;
    if (chapters.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsetsDirectional.only(start: 4, bottom: 10),
          child: Text('الأبواب', style: TextStyle(fontFamily: kUiFont, fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: chapters.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 130, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1),
          itemBuilder: (context, i) {
            final c = chapters[i];
            final fresh = repo.newChapters.contains(c.id);
            return Material(
              color: Pal.card(context),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20), side: BorderSide(color: Pal.line(context))),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChapterScreen(chapter: c))),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(chapterIcon(c.icon), color: kGoldChip, size: 30),
                    const SizedBox(height: 8),
                    Text(c.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(fresh ? 'جديد' : '${repo.countInChapter(c.id)}',
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: fresh ? FontWeight.bold : FontWeight.normal,
                            color: fresh ? const Color(0xFFC62828) : Pal.muted(context))),
                  ]),
                ),
              ),
            );
          },
        ),
      ]),
    );
  }
}
