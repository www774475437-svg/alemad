"""Adds the written pieces of the sheikh's site (articles, fatwas, written
refutations) to the app's answers, each in its chapter. Run after
fetch_telegram.py, from the repository root."""
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from channel_to_answers import DATA, classify  # noqa: E402

URL = 'https://raw.githubusercontent.com/www774475437-svg/alemad/site/texts.json'
FIXED = {'الردود المكتوبة': 'manhaj', 'التنبيهات': 'manhaj'}


def main():
    try:
        with urllib.request.urlopen(URL, timeout=60) as r:
            texts = json.loads(r.read().decode('utf-8'))
    except Exception as e:  # noqa
        print('site.json not reached:', e)
        return
    path = os.path.join(DATA, 'fatwas.json')
    answers = json.load(open(path, encoding='utf-8'))
    have = {a['id'] for a in answers}
    new = []
    for t in texts:
        fid = 'site-' + t['id']
        if fid in have:
            continue
        chapter = FIXED.get(t['section']) or classify(t['text'], t['title'])
        if chapter == 'mutafarriq' and t['section'] == 'فقه المعاملات':
            chapter = 'muamalat'
        is_fatwa = t['type'] == 'fatwa'
        new.append({
            'id': fid, 'chapter': chapter, 'type': t['type'], 'title': t['title'],
            'question': t['title'] if is_fatwa else '', 'answer': t['text'], 'tags': [t['section']],
            'date': t.get('date', ''), 'source': t.get('source', ''), 'audio': t.get('audio', ''),
        })
    if not new:
        print('no written pieces to add')
        return
    answers += new
    json.dump(answers, open(path, 'w', encoding='utf-8'), ensure_ascii=False)
    lp = os.path.join(DATA, 'latest.json')
    try:
        latest = json.load(open(lp, encoding='utf-8'))
    except Exception:  # noqa
        latest = []
    json.dump((latest + new)[-160:], open(lp, 'w', encoding='utf-8'), ensure_ascii=False)
    print('written pieces added:', len(new))


if __name__ == '__main__':
    main()
