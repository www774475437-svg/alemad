import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../services/site_data.dart';
import '../theme.dart';
import '../widgets/auto_row.dart';
import '../widgets/common.dart';
import '../widgets/source_book.dart' show openBook;
import 'ask_screen.dart';
import 'books_tab.dart';
import 'sections.dart' show ChapterGrid;
import 'site_screens.dart';
import 'trusted_screens.dart';

// The app follows the sheikh's own site: the same sections, in the same
// order, each with its own page, and the same «جديد …» rows on the home page.

void _push(BuildContext context, Widget page) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

int _no(String id) => int.tryParse(id.split('-').last) ?? 0;

/// The written pieces of the site under these section names, newest first.
List<Fatwa> siteTexts(List<String> sections) {
  final list = [
    for (final f in Repository.instance.fatwas)
      if (f.id.startsWith('site-') && f.tags.any(sections.contains)) f
  ]..sort((a, b) => _no(b.id).compareTo(_no(a.id)));
  return list;
}

/// What was written in the sheikh's channel, newest first.
List<Fatwa> channelTexts() => [
      for (final f in Repository.instance.fatwas)
        if (f.id.startsWith('tg-')) f
    ]..sort((a, b) => _no(b.id).compareTo(_no(a.id)));

SiteGroup? _group(String name) {
  for (final g in SiteData.instance.audio) {
    if (g.name == name) return g;
  }
  return null;
}

// ------------------------------------------------------------------ titles

/// The title of a row on the home page, with «المزيد» at its end.
class SectionHead extends StatelessWidget {
  final String text;
  final VoidCallback? onMore;
  const SectionHead(this.text, {super.key, this.onMore});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 24, 8, 10),
        child: Row(children: [
          Container(
              width: 6,
              height: 28,
              decoration: BoxDecoration(color: kGold, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontFamily: kUiFont, fontSize: 22, fontWeight: FontWeight.bold)),
          ),
          if (onMore != null)
            TextButton(
              onPressed: onMore,
              child: const Text('المزيد', style: TextStyle(fontFamily: kUiFont, fontWeight: FontWeight.bold)),
            ),
        ]),
      );
}

/// The button under a big row: «المزيد» opens the whole section.
class MoreBar extends StatelessWidget {
  final VoidCallback onTap;
  const MoreBar({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            side: const BorderSide(color: kGold, width: 1.2),
          ),
          child: const Text('المزيد', style: TextStyle(fontFamily: kUiFont, fontWeight: FontWeight.bold, fontSize: 16)),
        ),
      );
}

// ------------------------------------------------------------------ the sections

/// The sections of the sheikh's site, in its own order, as one grid.
class SiteSectionsGrid extends StatelessWidget {
  const SiteSectionsGrid({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SiteData.instance,
        builder: (context, _) {
          final items = <(IconData, String, Widget)>[
            (Icons.badge_outlined, 'الترجمة', const BioScreen()),
            (Icons.menu_book_rounded, 'التلاوات', const AudioGroupScreen(group: 'التلاوات')),
            (Icons.school_rounded, 'الدروس', const SiteLessonsScreen()),
            (Icons.campaign_rounded, 'الخطب والمحاضرات', const AudioGroupScreen(group: 'الخطب والمحاضرات')),
            (Icons.shield_outlined, 'الردود', const AudioGroupScreen(group: 'الردود')),
            (Icons.article_outlined, 'المقالات', const ArticlesScreen()),
            (Icons.question_answer_outlined, 'الفتاوى', const TextsScreen(title: 'الفتاوى', sections: ['فقه العبادات', 'فقه المعاملات'])),
            (Icons.edit_note_rounded, 'القصائد', const TextsScreen(title: 'القصائد', sections: ['القصائد'])),
            (Icons.auto_stories_rounded, 'المؤلفات', const BooksTab()),
            (Icons.folder_copy_outlined, 'الوثائق', const DocsScreen()),
            (Icons.forum_rounded, 'اسأل الشيخ', const AskScreen()),
            (Icons.groups_rounded, 'المشايخ الثقات', const TrustedScholarsScreen()),
          ];
          final wide = MediaQuery.sizeOf(context).width;
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
            child: GridView.count(
              crossAxisCount: wide > 900 ? 6 : (wide > 560 ? 4 : 3),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.12,
              children: [
                for (final it in items)
                  Material(
                    color: Pal.card(context),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18), side: BorderSide(color: Pal.line(context))),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => _push(context, it.$3),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          CircleAvatar(
                              radius: 21,
                              backgroundColor: kGold.withValues(alpha: .18),
                              child: Icon(it.$1, color: kGoldChip, size: 24)),
                          const SizedBox(height: 8),
                          Text(it.$2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontFamily: kUiFont, fontSize: 13, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
}

// ------------------------------------------------------------------ rows of the home page

/// «جديد …»: the newest recordings of one list of the site; one press plays.
class NewAudioRow extends StatefulWidget {
  final String listKey, title, group;
  /// Big cards with a «المزيد» bar under them (khutab, lectures, replies).
  final bool big;
  const NewAudioRow({super.key, required this.listKey, required this.title, required this.group, this.big = false});

  @override
  State<NewAudioRow> createState() => _NewAudioRowState();
}

class _NewAudioRowState extends State<NewAudioRow> {
  SiteList? _list;
  List<SiteTrack> _tracks = const [];
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    SiteData.instance.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    SiteData.instance.removeListener(_load);
    super.dispose();
  }

  void _load() {
    if (_asked) return;
    final list = SiteData.instance.listOf(widget.listKey);
    if (list == null) return;
    _asked = true;
    SiteData.instance.tracks(list.key).then((t) {
      if (!mounted || t.isEmpty) return;
      final newest = [...t]..sort((a, b) => b.id.compareTo(a.id));
      setState(() {
        _list = list;
        _tracks = newest.take(10).toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    if (list == null || _tracks.isEmpty) return const SizedBox.shrink();
    if (widget.big) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SectionHead(widget.title),
        AutoRow(
          height: 176,
          step: 284,
          gap: 12,
          every: const Duration(seconds: 5),
          itemCount: _tracks.length,
          itemBuilder: (context, i) => SizedBox(
            width: 272,
            child: Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => playTracks(context, list, _tracks, i),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: kGold,
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
                      ),
                      const Spacer(),
                      Text(widget.group,
                          style: TextStyle(fontFamily: kUiFont, fontSize: 12, color: Pal.muted(context))),
                    ]),
                    const SizedBox(height: 10),
                    Expanded(
                      child: Text(_tracks[i].title,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: kUiFont, height: 1.6, fontSize: 15.5, fontWeight: FontWeight.bold)),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
        MoreBar(onTap: () => _push(context, AudioGroupScreen(group: widget.group))),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHead(widget.title, onMore: () => _push(context, AudioGroupScreen(group: widget.group))),
      AutoRow(
        height: 122,
        step: 232,
        gap: 10,
        every: const Duration(seconds: 5),
        itemCount: _tracks.length,
        itemBuilder: (context, i) => SizedBox(
          width: 222,
          child: Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => playTracks(context, list, _tracks, i),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  CircleAvatar(
                    radius: 19,
                    backgroundColor: kGold.withValues(alpha: 0.2),
                    child: const Icon(Icons.play_arrow_rounded, color: kGoldChip, size: 24),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_tracks[i].title,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(height: 1.5, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// «الدروس»: the fields of knowledge, each opening its lessons.
class LessonFieldsRow extends StatelessWidget {
  const LessonFieldsRow({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SiteData.instance,
        builder: (context, _) {
          final fields = SiteData.instance.lessons;
          if (fields.isEmpty) return const SizedBox.shrink();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHead('الدروس', onMore: () => _push(context, const SiteLessonsScreen())),
            AutoRow(
              height: 104,
              step: 172,
              gap: 10,
              every: const Duration(seconds: 4),
              itemCount: fields.length,
              itemBuilder: (context, i) => SizedBox(
                width: 162,
                child: Material(
                  color: brandColor(context),
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => _push(context, SiteLessonsScreen(initial: i)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.school_rounded, color: kGold, size: 24),
                        const Spacer(),
                        Text(fields[i].name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontFamily: kUiFont, color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14.5)),
                        Text('${fields[i].lists.length} شرحاً · ${fields[i].count} درساً',
                            style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      );
}

/// A row of written pieces (articles, fatwas, poems).
class TextsRow extends StatelessWidget {
  final String title;
  final List<Fatwa> items;
  final Widget more;
  /// Poems: the first verses are shown with their line breaks kept.
  final bool poem;
  const TextsRow({super.key, required this.title, required this.items, required this.more, this.poem = false});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final shown = items.take(10).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHead(title),
      AutoRow(
        height: 214,
        step: 306,
        gap: 12,
        every: const Duration(seconds: 6),
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final f = shown[i];
          final body = poem
              ? f.answer.trim()
              : f.answer.replaceAll('\n', ' ').trim();
          final cut = body.length > 260 ? body.substring(0, 260) : body;
          return SizedBox(
            width: 292,
            child: Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => openFatwa(context, f),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(f.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: kUiFont, height: 1.5, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(cut,
                          maxLines: poem ? 6 : 5,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: poem ? 'Amiri' : kUiFont,
                              height: 1.7,
                              fontSize: poem ? 15 : 13.5,
                              color: Pal.muted(context))),
                    ),
                  ]),
                ),
              ),
            ),
          );
        },
      ),
      MoreBar(onTap: () => _push(context, more)),
    ]);
  }
}

/// «جديد المؤلفات»: the newest books of the sheikh.
class NewBooksRow extends StatelessWidget {
  const NewBooksRow({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SiteData.instance,
        builder: (context, _) {
          final books = [...SiteData.instance.books]..sort((a, b) => _no(b.id).compareTo(_no(a.id)));
          if (books.isEmpty) return const SizedBox.shrink();
          final shown = books.take(10).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SectionHead('جديد المؤلفات', onMore: () => _push(context, const BooksTab())),
            AutoRow(
              height: 118,
              step: 212,
              gap: 10,
              every: const Duration(seconds: 5),
              itemCount: shown.length,
              itemBuilder: (context, i) => SizedBox(
                width: 202,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => openBook(context, shown[i]),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.auto_stories_rounded, color: kGoldChip, size: 28),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(shown[i].title,
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(height: 1.5, fontWeight: FontWeight.w600)),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
            ),
          ]);
        },
      );
}

// ------------------------------------------------------------------ the pages of the sections

/// «الترجمة»
class BioScreen extends StatelessWidget {
  const BioScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ترجمة الشيخ')),
        body: ListenableBuilder(
          listenable: SiteData.instance,
          builder: (context, _) {
            final bio = SiteData.instance.bio.trim();
            if (bio.isEmpty) {
              return const EmptyState(icon: Icons.badge_outlined, text: 'تُحمَّل الترجمة…\nتأكد من الإنترنت ثم عد بعد قليل.');
            }
            return SelectionArea(
              child: ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 120), children: [
                Text(bio, style: const TextStyle(fontSize: 18, height: 2.0)),
              ]),
            );
          },
        ),
      );
}

/// One group of recordings of the site («التلاوات», «الخطب والمحاضرات»,
/// «الردود») with its lists as the site orders them, and what is written of it.
class AudioGroupScreen extends StatelessWidget {
  final String group;
  const AudioGroupScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(group)),
        body: ListenableBuilder(
          listenable: Listenable.merge([SiteData.instance, Repository.instance]),
          builder: (context, _) {
            final g = _group(group);
            final written = siteTexts(group == 'الردود'
                ? const ['الردود المكتوبة']
                : group == 'الخطب والمحاضرات'
                    ? const ['الخطب المفرغة']
                    : const []);
            if (g == null && written.isEmpty) {
              return const EmptyState(icon: Icons.headphones_outlined, text: 'تُحمَّل القائمة…');
            }
            return ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 120), children: [
              if (g != null)
                for (final l in g.lists) SiteListCard(key: ValueKey(l.key), list: l, icon: Icons.headphones_rounded),
              if (written.isNotEmpty) ...[
                SectionHead(group == 'الردود' ? 'الردود المكتوبة' : 'الخطب المفرغة'),
                for (final f in written) FatwaTile(fatwa: f),
              ],
            ]);
          },
        ),
      );
}

/// «الدروس»
class SiteLessonsScreen extends StatelessWidget {
  final int initial;
  const SiteLessonsScreen({super.key, this.initial = 0});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(title: const Text('الدروس')), body: SiteLessonsView(initial: initial));
}

/// Written pieces under one or more section names, a tab for each.
class TextsScreen extends StatelessWidget {
  final String title;
  final List<String> sections;
  const TextsScreen({super.key, required this.title, required this.sections});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: sections.length,
        child: Scaffold(
          appBar: AppBar(
            title: Text(title),
            bottom: sections.length < 2 ? null : TabBar(tabs: [for (final s in sections) Tab(text: s)]),
          ),
          body: ListenableBuilder(
            listenable: Repository.instance,
            builder: (context, _) => TabBarView(children: [for (final s in sections) _TextList(items: siteTexts([s]))]),
          ),
        ),
      );
}

class _TextList extends StatelessWidget {
  final List<Fatwa> items;
  const _TextList({required this.items});

  @override
  Widget build(BuildContext context) => items.isEmpty
      ? const EmptyState(icon: Icons.article_outlined, text: 'لا شيء هنا بعد.')
      : ListView.builder(
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 120),
          itemCount: items.length,
          itemBuilder: (context, i) => FatwaTile(fatwa: items[i]),
        );
}

/// «المقالات»: the site's two kinds, then what was written in the channel.
class ArticlesScreen extends StatelessWidget {
  const ArticlesScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('المقالات'),
            bottom: const TabBar(tabs: [Tab(text: 'المقالات العامة'), Tab(text: 'التنبيهات'), Tab(text: 'من القناة')]),
          ),
          body: ListenableBuilder(
            listenable: Repository.instance,
            builder: (context, _) => TabBarView(children: [
              _TextList(items: siteTexts(const ['المقالات العامة'])),
              _TextList(items: siteTexts(const ['التنبيهات'])),
              ListView(padding: const EdgeInsets.only(bottom: 120), children: [
                const ChapterGrid(),
                const SizedBox(height: 8),
                for (final f in channelTexts().take(40)) FatwaTile(fatwa: f),
              ]),
            ]),
          ),
        ),
      );
}

/// «الوثائق»: the sections of documents; each opens in place.
class DocsScreen extends StatelessWidget {
  const DocsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('الوثائق')),
        body: ListenableBuilder(
          listenable: SiteData.instance,
          builder: (context, _) {
            final cats = SiteData.instance.docs;
            if (cats.isEmpty) {
              return const EmptyState(icon: Icons.folder_copy_outlined, text: 'تُحمَّل الوثائق…\nتأكد من الإنترنت ثم عد بعد قليل.');
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
              children: [for (final c in cats) _DocCat(key: ValueKey(c.key), cat: c)],
            );
          },
        ),
      );
}

class _DocCat extends StatefulWidget {
  final SiteList cat;
  const _DocCat({super.key, required this.cat});

  @override
  State<_DocCat> createState() => _DocCatState();
}

class _DocCatState extends State<_DocCat> {
  bool _open = false;
  List<Map>? _items;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open && _items == null) {
      SiteData.instance.docItems(widget.cat.key).then((i) {
        if (mounted) setState(() => _items = i);
      });
    }
  }

  static String _first(Map m, String k) {
    final v = m[k];
    return v is List && v.isNotEmpty ? '${v.first}' : '';
  }

  void _openDoc(List<Map> items, int at) {
    final d = items[at];
    final audio = _first(d, 'audio'), img = _first(d, 'img');
    if (audio.isNotEmpty) {
      // Every sound document of the section, as one queue.
      final sounds = [
        for (final x in items)
          if (_first(x, 'audio').isNotEmpty) SiteTrack((x['id'] as num).toInt(), '${x['t'] ?? ''}', _first(x, 'audio'))
      ];
      final i = sounds.indexWhere((t) => t.id == (d['id'] as num).toInt());
      playTracks(context, widget.cat, sounds, i < 0 ? 0 : i);
    } else if (img.isNotEmpty) {
      _push(context, _DocImage(title: '${d['t'] ?? ''}', urls: [for (final u in (d['img'] as List)) '$u']));
    } else {
      final other = _first(d, 'video').isNotEmpty ? _first(d, 'video') : _first(d, 'file');
      if (other.isNotEmpty) openUrl(context, other);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          leading: CircleAvatar(
              radius: 24,
              backgroundColor: kGold.withValues(alpha: .18),
              child: const Icon(Icons.folder_copy_outlined, color: kGoldChip)),
          title: Text(widget.cat.name,
              style: const TextStyle(fontFamily: kUiFont, fontWeight: FontWeight.bold, fontSize: 14.5, height: 1.6)),
          subtitle: Text('${widget.cat.count} وثيقة'),
          trailing: Icon(_open ? Icons.expand_less : Icons.expand_more),
          onTap: _toggle,
        ),
        if (_open && items == null)
          const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator())),
        if (_open && items != null && items.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('تعذّر التحميل، تأكد من الإنترنت ثم أعد المحاولة.')),
        if (_open && items != null && items.isNotEmpty) ...[
          const Divider(height: 1),
          for (var i = 0; i < items.length; i++)
            ListTile(
              dense: true,
              leading: Icon(
                  _first(items[i], 'audio').isNotEmpty
                      ? Icons.play_circle_outline_rounded
                      : _first(items[i], 'img').isNotEmpty
                          ? Icons.image_outlined
                          : _first(items[i], 'video').isNotEmpty
                              ? Icons.smart_display_outlined
                              : Icons.insert_drive_file_outlined,
                  color: kGoldChip),
              title: Text('${items[i]['t'] ?? ''}', style: const TextStyle(fontSize: 14.5, height: 1.6)),
              onTap: () => _openDoc(items, i),
            ),
        ],
      ]),
    );
  }
}

/// A document that is a picture (or several): shown inside the app, zoomable.
class _DocImage extends StatelessWidget {
  final String title;
  final List<String> urls;
  const _DocImage({required this.title, required this.urls});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis)),
        body: ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 120), children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, height: 1.8)),
          ),
          for (final u in urls)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InteractiveViewer(
                maxScale: 5,
                child: Image.network(u,
                    fit: BoxFit.fitWidth,
                    loadingBuilder: (context, child, p) => p == null
                        ? child
                        : const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
                    errorBuilder: (context, e, s) => Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(children: [
                            const Text('تعذّر عرض الصورة هنا.'),
                            TextButton(onPressed: () => openUrl(context, u), child: const Text('افتحها من موقع الشيخ')),
                          ]),
                        )),
              ),
            ),
        ]),
      );
}
