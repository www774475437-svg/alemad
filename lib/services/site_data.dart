import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/repository.dart';

/// One recording of the sheikh's official site.
class SiteTrack {
  final int id;
  final String title, url;
  const SiteTrack(this.id, this.title, this.url);
  factory SiteTrack.fromJson(Map m) => SiteTrack((m['id'] as num).toInt(), '${m['t'] ?? ''}', '${m['u'] ?? ''}');
}

/// A named list of recordings (a section of sermons, or one lesson series).
/// Only its name and size are known at first; its recordings are read when
/// the listener opens it.
class SiteList {
  final String key; // «s6» a section, «c78» a lesson series
  final String name;
  final int count;
  const SiteList(this.key, this.name, this.count);
  factory SiteList.fromJson(Map m) => SiteList('${m['key']}', '${m['name'] ?? ''}', (m['n'] as num? ?? 0).toInt());
}

class SiteGroup {
  final String name;
  final List<SiteList> lists;
  const SiteGroup(this.name, this.lists);
  int get count => lists.fold(0, (a, l) => a + l.count);
}

/// One result of the search in the titles of all recordings.
class SiteHit {
  final SiteList list;
  final int at;
  final String title;
  const SiteHit(this.list, this.at, this.title);
}

/// What the sheikh's official site holds. The app opens with a small index
/// only; every list, and the titles for the search, are read when asked for
/// and then kept on the device.
class SiteData extends ChangeNotifier {
  SiteData._();
  static final SiteData instance = SiteData._();

  static const _base = 'https://raw.githubusercontent.com/www774475437-svg/alemad/site/';
  static const _fixed = {'الردود المكتوبة': 'manhaj', 'التنبيهات': 'manhaj', 'فقه المعاملات': 'muamalat'};

  List<SiteGroup> audio = [];
  List<SiteGroup> lessons = [];
  List<Book> books = [];
  SiteTrack? khutba; // the newest Friday sermon

  List<Book> get levels => books.where((b) => b.level > 0).toList()..sort((a, b) => a.level.compareTo(b.level));
  Book? get wholeSet {
    for (final b in books) {
      if (b.level == 0) return b;
    }
    return null;
  }

  int get audioCount => audio.fold(0, (a, g) => a + g.count);

  SiteList? listOf(String key) {
    for (final g in [...audio, ...lessons]) {
      for (final l in g.lists) {
        if (l.key == key) return l;
      }
    }
    return null;
  }

  bool _started = false;

  /// Called after the first screen is up, so opening stays fast.
  Future<void> load() async {
    if (_started) return;
    _started = true;
    final prefs = await SharedPreferences.getInstance();
    try {
      final saved = prefs.getString('site_index');
      _apply(jsonDecode(saved ?? await rootBundle.loadString('assets/data/site.json')) as Map);
      notifyListeners();
    } catch (e) {
      debugPrint('site index: $e');
    }
    try {
      final res = await http.get(Uri.parse('${_base}index.json')).timeout(const Duration(seconds: 25));
      if (res.statusCode == 200) {
        final body = utf8.decode(res.bodyBytes);
        final m = jsonDecode(body) as Map;
        if ((m['audio'] as List? ?? const []).isNotEmpty) {
          _apply(m);
          notifyListeners();
          try {
            await prefs.setString('site_index', body);
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('site index (net): $e');
    }
    // Written pieces newer than this copy join later, when all is quiet.
    Timer(const Duration(seconds: 25), _newTexts);
  }

  void _apply(Map m) {
    List<SiteGroup> groups(String field, String name, String inner) => [
          for (final g in (m[field] as List? ?? const []))
            SiteGroup('${(g as Map)[name] ?? ''}',
                [for (final c in (g[inner] as List? ?? const [])) if ((c as Map)['key'] != null) SiteList.fromJson(c)])
        ];
    final a = groups('audio', 'group', 'cats'), l = groups('lessons', 'name', 'courses');
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
    if (a.isEmpty && l.isEmpty && b.isEmpty) return;
    audio = a;
    lessons = l;
    books = b;
    final k = m['khutba'];
    khutba = k is Map ? SiteTrack.fromJson(k) : null;
    if (b.isNotEmpty) Repository.instance.setBooks(b);
  }

  // ------------------------------------------------------------ one list
  final Map<String, List<SiteTrack>> _lists = {};

  static List<SiteTrack> _parse(String body) =>
      [for (final e in ((jsonDecode(body) as Map)['items'] as List? ?? const [])) SiteTrack.fromJson(e as Map)];

  /// The recordings of one list: from memory, else from the device, else
  /// from the net (then kept). A kept list is renewed quietly once a day.
  Future<List<SiteTrack>> tracks(String key) async {
    final mem = _lists[key];
    if (mem != null) return mem;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('site_list_$key');
    if (saved != null) {
      try {
        final list = _lists[key] = _parse(saved);
        final at = prefs.getInt('site_list_at_$key') ?? 0;
        if (DateTime.now().millisecondsSinceEpoch - at > 24 * 3600 * 1000) unawaited(_fetchList(key, prefs));
        return list;
      } catch (_) {}
    }
    return await _fetchList(key, prefs) ?? const [];
  }

  Future<List<SiteTrack>?> _fetchList(String key, SharedPreferences prefs) async {
    try {
      final res = await http.get(Uri.parse('${_base}lists/$key.json')).timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return null;
      final body = utf8.decode(res.bodyBytes);
      final list = _lists[key] = _parse(body);
      try {
        await prefs.setString('site_list_$key', body);
        await prefs.setInt('site_list_at_$key', DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}
      return list;
    } catch (e) {
      debugPrint('list $key: $e');
      return null;
    }
  }

  // ------------------------------------------------------------ search
  Map<String, List<String>>? _titles;
  Future<void>? _titlesLoad;

  /// The titles of all recordings, read the first time one searches.
  Future<void> loadTitles() => _titlesLoad ??= () async {
        try {
          final res = await http.get(Uri.parse('${_base}titles.json')).timeout(const Duration(seconds: 30));
          if (res.statusCode != 200) throw Exception('${res.statusCode}');
          final m = jsonDecode(utf8.decode(res.bodyBytes)) as Map;
          _titles = {for (final e in m.entries) '${e.key}': [for (final t in ((e.value as Map)['t'] as List)) '$t']};
        } catch (e) {
          _titlesLoad = null; // try again next time
          debugPrint('titles: $e');
        }
      }();

  static String norm(String s) => s
      .replaceAll(RegExp('[ً-ْٰـ]'), '')
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي')
      .toLowerCase();

  List<SiteHit> search(String query, {int limit = 60}) {
    final t = _titles;
    final words = norm(query).split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (t == null || words.isEmpty) return const [];
    final out = <SiteHit>[];
    for (final e in t.entries) {
      final list = listOf(e.key);
      if (list == null) continue;
      for (var i = 0; i < e.value.length; i++) {
        final n = norm(e.value[i]);
        if (words.every(n.contains)) {
          out.add(SiteHit(list, i, e.value[i]));
          if (out.length >= limit) return out;
        }
      }
    }
    return out;
  }

  // ------------------------------------------------------------ texts
  Future<void> _newTexts() async {
    try {
      final res = await http.get(Uri.parse('${_base}texts.json')).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) return;
      final texts = [
        for (final t in (jsonDecode(utf8.decode(res.bodyBytes)) as List))
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
      if (texts.isNotEmpty) Repository.instance.addLive(texts, const []);
    } catch (e) {
      debugPrint('texts: $e');
    }
  }
}
