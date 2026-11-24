import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../data/models.dart';
import '../data/repository.dart';

/// One recording of the sheikh's official site.
class SiteTrack {
  final int id;
  final String title, url;
  const SiteTrack(this.id, this.title, this.url);
  factory SiteTrack.fromJson(Map m) => SiteTrack((m['id'] as num).toInt(), '${m['t'] ?? ''}', '${m['u'] ?? ''}');
}

/// A named list of recordings: a section of sermons, or one lesson series.
class SiteList {
  final int id;
  final String name;
  final List<SiteTrack> items;
  const SiteList(this.id, this.name, this.items);
  factory SiteList.fromJson(Map m) => SiteList((m['id'] as num).toInt(), '${m['name'] ?? ''}',
      [for (final e in (m['items'] as List? ?? const [])) SiteTrack.fromJson(e as Map)]);
}

/// A group of lists: «التلاوات» with its sections, or a field of knowledge
/// with its lesson series.
class SiteGroup {
  final String name;
  final List<SiteList> lists;
  const SiteGroup(this.name, this.lists);
  int get count => lists.fold(0, (a, l) => a + l.items.length);
}

/// What the sheikh's official site holds: his recordings by section, his
/// lesson series and his books. Read once from the copy that comes with the
/// app, then refreshed from the net (a small file renewed a few times a day),
/// so new recordings appear without an update.
class SiteData extends ChangeNotifier {
  SiteData._();
  static final SiteData instance = SiteData._();

  static const _url = 'https://raw.githubusercontent.com/www774475437-svg/alemad/site/site.json';

  static const _fixed = {'الردود المكتوبة': 'manhaj', 'التنبيهات': 'manhaj', 'فقه المعاملات': 'muamalat'};

  List<SiteGroup> audio = [];
  List<SiteGroup> lessons = [];
  List<Book> books = [];
  bool loaded = false;

  /// The seven levels of «مفتاح العلوم», in order, then the whole set.
  List<Book> get levels => books.where((b) => b.level > 0).toList()..sort((a, b) => a.level.compareTo(b.level));
  Book? get wholeSet {
    for (final b in books) {
      if (b.level == 0) return b;
    }
    return null;
  }

  int get audioCount => audio.fold(0, (a, g) => a + g.count);
  int get lessonCount => lessons.fold(0, (a, g) => a + g.count);

  Future<void> load() async {
    try {
      _apply(jsonDecode(await rootBundle.loadString('assets/data/site.json')) as Map);
    } catch (e) {
      debugPrint('site.json (bundled): $e');
    }
    loaded = true;
    notifyListeners();
    refresh();
  }

  Future<void> refresh() async {
    try {
      final res = await http.get(Uri.parse(_url)).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return;
      final m = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
      _apply(m);
      notifyListeners();
      // Written pieces newer than this copy join once everything else is loaded.
      Future.delayed(const Duration(seconds: 12), () => _apply(m, withTexts: true));
    } catch (e) {
      debugPrint('site.json (net): $e');
    }
  }

  void _apply(Map m, {bool withTexts = false}) {
    final a = [
      for (final g in (m['audio'] as List? ?? const []))
        SiteGroup('${(g as Map)['group'] ?? ''}', [for (final c in (g['cats'] as List? ?? const [])) SiteList.fromJson(c as Map)])
    ];
    final l = [
      for (final g in (m['lessons'] as List? ?? const []))
        SiteGroup('${(g as Map)['name'] ?? ''}', [for (final c in (g['courses'] as List? ?? const [])) SiteList.fromJson(c as Map)])
    ];
    final b = [
      for (final e in (m['books'] as List? ?? const []))
        Book(
          id: 'site-${(e as Map)['id']}',
          title: '${e['title'] ?? ''}',
          folder: '${e['art'] ?? ''}',
          url: '${e['pdf'] ?? ''}',
          source: '${e['src'] ?? ''}',
          cover: '${e['cover'] ?? ''}',
          about: '${e['about'] ?? ''}',
          level: e['level'] == null ? -1 : (e['level'] as num).toInt(),
        )
    ];
    if (a.isEmpty && l.isEmpty && b.isEmpty) return; // keep what we have
    audio = a;
    lessons = l;
    books = b;
    if (b.isNotEmpty) Repository.instance.setBooks(b);
    // Written pieces that arrived after this copy of the app was made.
    final texts = [
      for (final t in (m['texts'] as List? ?? const []))
        Fatwa(
          id: 'site-${(t as Map)['id']}',
          chapter: _fixed['${t['section']}'] ?? 'mutafarriq',
          type: '${t['type'] ?? 'article'}',
          title: '${t['title'] ?? ''}',
          question: t['type'] == 'fatwa' ? '${t['title'] ?? ''}' : '',
          answer: '${t['text'] ?? ''}',
          tags: ['${t['section'] ?? ''}'],
          date: '${t['date'] ?? ''}',
          source: '${t['source'] ?? ''}',
          audio: '${t['audio'] ?? ''}',
        )
    ];
    if (withTexts && texts.isNotEmpty) Repository.instance.addLive(texts, const []);
  }
}
