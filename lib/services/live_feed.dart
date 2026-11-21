import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'telegram_out.dart';

import '../data/models.dart';
import '../data/repository.dart';

/// Reads the sheikh's channel directly on the phone, so a new post shows a
/// few minutes after it is published, without a new version and without
/// waiting for the daily site data (which later replaces it with its copy,
/// already sorted into its chapter). Android only: the site cannot read
/// Telegram directly.
/// What arrives is kept on the phone, so it stays even offline.
class LiveFeed {
  static const _channel = 'salmansalehalemad';
  static bool _busy = false;

  static Future<void> refresh({bool force = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _restore(prefs);
      final now = DateTime.now().millisecondsSinceEpoch;
      // The channel itself: at most every 5 minutes.
      if (!kIsWeb && (force || now - (prefs.getInt('liveTgAt') ?? 0) > 5 * 60 * 1000)) {
        if (await _fromTelegram(prefs)) await prefs.setInt('liveTgAt', now);
      }
    } catch (e) {
      debugPrint('live feed: $e');
    }
    _busy = false;
  }

  /// What came before (kept on the phone).
  static void _restore(SharedPreferences prefs) {
    try {
      final f = jsonDecode(prefs.getString('liveFatwas') ?? '[]') as List;
      final c = jsonDecode(prefs.getString('liveChannel') ?? '[]') as List;
      Repository.instance.addLive(
        [for (final e in f) Fatwa.fromJson(e as Map<String, dynamic>)],
        [for (final e in c) ChannelPost.fromJson(e as Map<String, dynamic>)],
      );
    } catch (_) {}
  }

  static Future<void> _keep(SharedPreferences prefs, List<Map<String, dynamic>> f, List<Map<String, dynamic>> c) async {
    List old(String k) {
      try {
        return jsonDecode(prefs.getString(k) ?? '[]') as List;
      } catch (_) {
        return [];
      }
    }

    final of = old('liveFatwas'), oc = old('liveChannel');
    final ids = {for (final e in of) '${(e as Map)['id']}'};
    final cids = {for (final e in oc) '${(e as Map)['id']}'};
    final nf = [...of, for (final e in f) if (ids.add('${e['id']}')) e];
    final nc = [...oc, for (final e in c) if (cids.add('${e['id']}')) e];
    // Keep the newest 400 only; a newer version of the app carries the rest.
    int key(Object? e) => int.tryParse('${(e as Map)['id']}'.replaceFirst('tg-', '')) ?? 0;
    nf.sort((a, b) => key(b).compareTo(key(a)));
    nc.sort((a, b) => key(b).compareTo(key(a)));
    await prefs.setString('liveFatwas', jsonEncode(nf.take(400).toList()));
    await prefs.setString('liveChannel', jsonEncode(nc.take(400).toList()));
  }

  // ------------------------------------------------------------ Telegram

  static String clean(String fragment) {
    var t = fragment.replaceAll(RegExp(r'<br\s*/?>'), '\n').replaceAll(RegExp(r'<[^>]+>'), '');
    t = t
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
    t = t.replaceAll(RegExp(r'[ \t]+\n'), '\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return t.trim();
  }

  // Same rules as the build (tool/channel_to_answers.py), so the post lands
  // in the same shape and the daily data later simply confirms it.
  static final _answerLine = RegExp(
      '^[^\\p{L}\\p{N}_\\n]*(?:(?:[وف]?\\s*الجواب|الإجابة)[^\\p{L}\\p{N}_\\n]*(?:[:：/][^\\p{L}\\p{N}_\\n]*|\$)|ج[ \\t]*[:：/]|فأجبت(?:ه|ها|هم)?[ \\t]*[:：])[ \\t]*\\n?',
      multiLine: true,
      unicode: true);
  static final _questionStart = RegExp(
      '^[^\\p{L}\\p{N}_\\n]*(?:السؤال|سؤال|س)\\s*[:：/]\\s*|^[^\\p{L}\\p{N}_\\n]*(?:يقول\\s*(?:السائل)?\\s*[:：]?)\\s*',
      unicode: true);
  static final _hashtags = RegExp(r'^\s*(?:#\S+\s*)+$', multiLine: true);
  static final _linkOnly = RegExp(r'^\s*(?:https?://\S+\s*)+$');

  static String titleOf(String text, [int limit = 90]) {
    for (var line in text.split('\n')) {
      line = line.replaceAll(RegExp(r'^[\s*_\-–—▪•🔹🔸📌❓⁉️]+|[\s*_\-–—▪•🔹🔸📌❓⁉️]+$'), '');
      if (line.length >= 8) {
        if (line.length > limit) {
          final cut = line.substring(0, limit);
          final sp = cut.lastIndexOf(' ');
          line = '${sp > 40 ? cut.substring(0, sp) : cut}…';
        }
        return line;
      }
    }
    return text.length > limit ? text.substring(0, limit) : text;
  }

  static (String, String)? _split(String text) {
    final m = _answerLine.firstMatch(text);
    if (m == null || m.start < 10) return null;
    final q = text.substring(0, m.start).replaceFirst(_questionStart, '').trim();
    final a = text.substring(m.end).trim();
    if (q.length < 8 || a.length < 8) return null;
    if (q.length > 900 || a.length < 60 || _answerLine.allMatches(text).length > 1) return null;
    if (a.length < 300 && a.contains('http')) return null;
    return (q, a);
  }

  static Set<int> _fromApp = {};

  static Future<bool> _fromTelegram(SharedPreferences prefs) async {
    try {
      _fromApp = await TelegramOut.postedIds();
    } catch (_) {}
    final known = Repository.instance.lastChannelId;
    final f = <Map<String, dynamic>>[];
    final c = <Map<String, dynamic>>[];
    // The channel's web preview is closed, so the bot collects its posts
    // into one small file (refreshed every ~10 minutes).
    final res = await http
        .get(Uri.parse('https://raw.githubusercontent.com/www774475437-svg/alemad/media/posts.json'))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) return false;
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    for (final e in list) {
      final m = e as Map;
      final id = (m['id'] as num).toInt();
      if (id <= known) continue;
      if (_fromApp.contains(id)) continue; // posted from the app: already inside
      var text = '${m['text'] ?? ''}';
      text = text.replaceAll(_hashtags, '').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
      if (text.length < 20 || _linkOnly.hasMatch(text)) continue;
      final d = '${m['date'] ?? ''}';
      final base = {'id': 'tg-$id', 'tags': <String>[], 'date': d, 'source': 'https://t.me/$_channel/$id'};
      final qa = _split(text);
      if (qa != null) {
        f.add({...base, 'chapter': 'mutafarriq', 'type': 'fatwa', 'title': titleOf(qa.$1), 'question': qa.$1, 'answer': qa.$2});
      } else if (text.length >= 220) {
        f.add({...base, 'chapter': 'mutafarriq', 'type': 'article', 'title': titleOf(text), 'question': '', 'answer': text});
      } else {
        c.add({'id': id, 'text': text, 'date': d});
      }
    }
    if (f.isEmpty && c.isEmpty) return true;
    Repository.instance.addLive(
      [for (final e in f) Fatwa.fromJson(e)],
      [for (final e in c) ChannelPost.fromJson(e)],
    );
    await _keep(prefs, f, c);
    return true;
  }

}
