"""Reads the sheikh's official site (sh-salman.com) and writes site.json:
his recordings by section, the lesson series, and his books.
Run with an output folder: python tool/fetch_site.py OUT [BOOKS_DIR]
When BOOKS_DIR is given, each book's PDF is copied there once (ID.pdf)."""
import html, json, os, re, sys, time, urllib.parse, urllib.request

BASE = 'https://sh-salman.com'
UA = {'User-Agent': 'Mozilla/5.0 (alemad-app)'}

AUDIO_GROUPS = [
    ('التلاوات', [1, 2, 3]),
    ('الخطب والمحاضرات', [6, 7, 8, 9]),
    ('الردود', [11, 12, 13, 14, 15, 16, 18]),
]
LESSON_CATS = [1, 2, 3, 4, 11, 12, 14, 15, 16]
# Written pieces: (list page, kind of item link, type in the app, section name)
TEXT_LISTS = [
    ('postscats/1', 'posts', 'article', 'المقالات العامة'),
    ('postscats/2', 'posts', 'article', 'التنبيهات'),
    ('fatawacat/1', 'fatawas', 'fatwa', 'فقه العبادات'),
    ('fatawacat/2', 'fatawas', 'fatwa', 'فقه المعاملات'),
    ('soundscat/10', 'sounds', 'article', 'الخطب المفرغة'),
    ('soundscat/17', 'sounds', 'article', 'الردود المكتوبة'),
    ('poemscats/1', 'poems', 'article', 'القصائد'),
]
DOC_CATS = [7, 6, 5, 4, 3, 2, 1]  # the order of the site's own menu


def get(url, tries=3):
    for i in range(tries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=40) as r:
                return r.read().decode('utf-8', 'replace')
        except Exception as e:  # noqa
            err = e
            time.sleep(2 + 2 * i)
    print('failed', url, err)
    return ''


def clean(t):
    t = html.unescape(re.sub(r'<[^>]+>', ' ', t)).replace('\xa0', ' ')
    t = re.sub(r'\.mp3\s*$', '', t.strip(), flags=re.I)
    return re.sub(r'\s+', ' ', t).strip(' *')


def enc(u):
    """A link with spaces and Arabic letters, made safe to open."""
    u = html.unescape(u.strip())
    p = urllib.parse.urlsplit(u)
    return urllib.parse.urlunsplit((p.scheme, p.netloc, urllib.parse.quote(urllib.parse.unquote(p.path), safe='/'), p.query, ''))


def heading(page):
    m = re.search(r'card-header bg-main text-center">\s*(.*?)\s*</div>', page, re.S)
    return clean(m.group(1)) if m else ''


def blocks(page):
    return re.findall(r'<li class="position-relative">(.*?)</li>', page, re.S)


def parse_sounds(page):
    out = []
    for b in blocks(page):
        m = re.search(r'href="[^"]*/sounds/(\d+)"[^>]*>(.*?)</a>', b, re.S)
        f = re.search(r'href="([^"]*/uploads/[^"]+\.(?:mp3|m4a|ogg|wav|aac))"', b, re.I)
        if m and f:
            out.append({'id': int(m.group(1)), 't': clean(m.group(2)), 'u': enc(f.group(1))})
    return out


def parse_course(page):
    out = []
    for b in blocks(page):
        m = re.search(r'href="[^"]*/audio/(\d+)"[^>]*>(.*?)</a>', b, re.S)
        f = re.search(r'href="([^"]*/uploads/[^"]+\.(?:mp3|m4a|ogg|wav|aac))"', b, re.I)
        if m and f:
            out.append({'id': int(m.group(1)), 't': clean(m.group(2)), 'u': enc(f.group(1))})
    return out


def parse_courses(page):
    return [(int(i), clean(t)) for i, t in re.findall(r'href="[^"]*/course/(\d+)" class="list-group-item">(.*?)</a>', page, re.S)]


def parse_author(page):
    def field(label):
        m = re.search(r'<b>\s*' + label + r'\s*:?\s*</b>(.*?)</p>', page, re.S)
        return clean(m.group(1)) if m else ''
    pdf = re.search(r'href="([^"]*/uploads/authors/pdf/[^"]+)"', page)
    img = re.search(r'<img src="([^"]*/uploads/authors/images/[^"]+)"', page)
    return {
        'title': field('عنوان').strip('«» '),
        'art': field('الفن'),
        'about': field('نبذة'),
        'cover': enc(img.group(1)) if img else '',
        'pdf': enc(pdf.group(1)) if pdf else '',
    }


def body_text(page):
    """The written text of an item page, without the leftovers of Word."""
    i = page.find('<div class="description">')
    if i < 0:
        return ''
    t = page[i + 25:]
    for stop in ('<!-- START FOOTER', '<div class="download'):
        j = t.find(stop)
        if j > 0:
            t = t[:j]
    t = re.sub(r'<!--.*?-->', '', t, flags=re.S)
    t = re.sub(r'<(style|script|xml)[^>]*>.*?</\1>', '', t, flags=re.S | re.I)
    t = t.replace('\r', '').replace('\n', ' ')
    t = re.sub(r'<br\s*/?>|</p>|</div>|</h\d>|</li>|</tr>', '\n', t, flags=re.I)
    t = html.unescape(re.sub(r'<[^>]+>', '', t)).replace('\xa0', ' ')
    out = []
    for line in (re.sub(r'[ \t]+', ' ', x).strip() for x in t.split('\n')):
        if line or (out and out[-1]):
            out.append(line)
    return '\n\n'.join(x for x in out if x).strip()


def parse_text_list(kind):
    def f(page):
        out = []
        for b in blocks(page):
            m = re.search(r'href="[^"]*/%s/(\d+)"[^>]*>(.*?)</a>' % kind, b, re.S)
            if not m:
                continue
            a = re.search(r'href="([^"]*/uploads/[^"]+\.(?:mp3|m4a))"', b, re.I)
            out.append({'id': int(m.group(1)), 't': clean(m.group(2)), 'audio': enc(a.group(1)) if a else ''})
        if not out:
            out = [{'id': i, 't': t, 'audio': ''} for i, t in links_of(page, kind)]
        return out
    return f


def links_of(page, kind):
    """Every item of a kind linked from a page, with the longest title it is given."""
    best = {}
    for i, t in re.findall(r'href="[^"]*/%s/(\d+)"[^>]*>(.*?)</a>' % kind, page, re.S):
        t = clean(t)
        if len(t) > len(best.get(int(i), '')):
            best[int(i)] = t
    return [(i, t) for i, t in best.items() if len(t) > 3]


def media_of(page, folder):
    """The files of an item page, by their kind."""
    out = {'audio': [], 'img': [], 'video': [], 'file': []}
    for u in dict.fromkeys(re.findall(r'(?:src|href)="([^"]*/uploads/%s[^"]+)"' % folder, page)):
        ext = u.rsplit('.', 1)[-1].lower()
        kind = ('audio' if ext in ('mp3', 'm4a', 'ogg', 'wav', 'aac') else 'img' if ext in ('png', 'jpg', 'jpeg', 'webp', 'gif')
                else 'video' if ext in ('mp4', 'mov', 'webm', 'mkv') else 'file')
        out[kind].append(enc(u))
    return out


def paged(url, parse, limit=80):
    """All the pages of a list, until one brings nothing new."""
    seen, out = set(), []
    for n in range(1, limit + 1):
        page = get(url + ('&' if '?' in url else '?') + 'page=%d' % n) if n > 1 else get(url)
        new = [x for x in parse(page) if (x['id'] if isinstance(x, dict) else x) not in seen]
        if not new:
            break
        for x in new:
            seen.add(x['id'] if isinstance(x, dict) else x)
        out += new
        time.sleep(.3)
    return out, (heading(page) if n == 1 else '')


def level_of(title):
    """The level (1-7) of a «مفاتيح العلوم» book, 0 for the whole set, else None."""
    if 'مفاتيح العلوم كاملا' in title:
        return 0
    m = re.match(r'\s*0?([1-7])\s*المفاتيح', title)
    return int(m.group(1)) if m else None


def main():
    out = sys.argv[1]
    books_dir = sys.argv[2] if len(sys.argv) > 2 else ''
    os.makedirs(out, exist_ok=True)
    data = {'v': 1, 'updated': time.strftime('%Y-%m-%d %H:%M', time.gmtime()), 'audio': [], 'lessons': [], 'books': []}

    for group, ids in AUDIO_GROUPS:
        cats = []
        for cid in ids:
            first = get('%s/soundscat/%d' % (BASE, cid))
            name = heading(first)
            items, _ = paged('%s/soundscat/%d' % (BASE, cid), parse_sounds)
            if items:
                cats.append({'id': cid, 'name': name or 'قسم %d' % cid, 'items': items})
            print(group, cid, name, len(items))
        if cats:
            data['audio'].append({'group': group, 'cats': cats})

    for cid in LESSON_CATS:
        page = get('%s/category/%d' % (BASE, cid))
        courses = []
        for crs, title in parse_courses(page):
            items, _ = paged('%s/course/%d' % (BASE, crs), parse_course)
            if items:
                courses.append({'id': crs, 'name': title, 'items': items})
            time.sleep(.2)
        if courses:
            data['lessons'].append({'id': cid, 'name': heading(page), 'courses': courses})
        print('lessons', cid, heading(page), len(courses))

    ids, _ = paged(BASE + '/authors', lambda p: [int(i) for i in re.findall(r'href="[^"]*/authors/(\d+)" class="btn btn-primary"', p)])
    for bid in ids:
        b = parse_author(get('%s/authors/%d' % (BASE, bid)))
        if not b['title'] or not b['pdf']:
            continue
        b['id'] = bid
        lv = level_of(b['title'])
        if lv is not None:
            b['level'] = lv
        b['src'] = b['pdf']
        if books_dir:
            path = os.path.join(books_dir, '%d.pdf' % bid)
            if not os.path.exists(path):
                try:
                    with urllib.request.urlopen(urllib.request.Request(b['pdf'], headers=UA), timeout=180) as r:
                        blob = r.read()
                    if blob[:4] == b'%PDF' and len(blob) < 95 * 1024 * 1024:
                        with open(path, 'wb') as f:
                            f.write(blob)
                except Exception as e:  # noqa
                    print('book not copied', bid, e)
            if os.path.exists(path):
                b['size'] = os.path.getsize(path)
                b['pdf'] = 'https://raw.githubusercontent.com/www774475437-svg/alemad/books/%d.pdf' % bid
        data['books'].append(b)
        time.sleep(.2)
    print('books', len(data['books']))

    data['texts'] = []
    for path, kind, typ, section in TEXT_LISTS:
        items, _ = paged('%s/%s' % (BASE, path), parse_text_list(kind))
        n = 0
        for it in items:
            page = get('%s/%s/%d' % (BASE, kind, it['id']))
            text = body_text(page)
            if kind == 'poems':
                # A poem kept as a picture or a file: say where it is.
                m = media_of(page, '')
                extra = [u for u in m['img'] + m['file'] if '/poems' in u or '/uploads/' in u and 'logo' not in u]
                if len(text) < 40 and extra:
                    text = (text + '\n\n' + '\n'.join(extra[:6])).strip()
            if len(text) < 40:
                continue
            d = re.search(r'float-start">\s*(\d{4}-\d\d-\d\d)', page)
            data['texts'].append({'id': '%s-%d' % (kind, it['id']), 'type': typ, 'section': section, 'title': it['t'],
                                  'text': text, 'date': d.group(1) if d else '', 'audio': it['audio'],
                                  'source': '%s/%s/%d' % (BASE, kind, it['id'])})
            n += 1
            time.sleep(.2)
        print('texts', section, n)

    # «الترجمة»: the sheikh's biography, as the site writes it.
    bio = body_text(get(BASE + '/posts/31'))
    print('bio', len(bio))

    # «الوثائق»: each section of documents with what every document holds.
    docs = []
    for cid in DOC_CATS:
        url = '%s/documents/category/%d' % (BASE, cid)
        name = ''
        for a, t in re.findall(r'href="[^"]*/documents/category/(\d+)"[^>]*>(.*?)</a>', get(BASE + '/documents'), re.S):
            if int(a) == cid and len(clean(t)) > len(name):
                name = clean(t)
        found, _ = paged(url, lambda p: [{'id': i, 't': t} for i, t in links_of(p, 'documents')], limit=30)
        items = []
        for it in sorted(found, key=lambda x: -x['id']):
            m = media_of(get('%s/documents/%d' % (BASE, it['id'])), 'documents')
            if any(m.values()):
                items.append({'id': it['id'], 't': it['t'], **{k: v for k, v in m.items() if v}})
            time.sleep(.2)
        if items:
            docs.append({'id': cid, 'name': name or 'وثائق %d' % cid, 'items': items})
        print('documents', cid, name[:40], len(items))

    n_audio = sum(len(c['items']) for g in data['audio'] for c in g['cats'])
    n_less = sum(len(c['items']) for l in data['lessons'] for c in l['courses'])
    print('audio', n_audio, 'lesson files', n_less)
    if n_audio + n_less == 0 and not data['books']:
        print('nothing read; keeping the old files')
        return 1

    def dump(name, obj):
        path = os.path.join(out, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(obj, f, ensure_ascii=False, separators=(',', ':'))

    # A small index the app opens with; each list is its own little file,
    # read only when the listener opens it.
    titles = {}
    for g in data['audio']:
        for c in g['cats']:
            key = 's%d' % c['id']
            dump('lists/%s.json' % key, {'name': c['name'], 'items': c['items']})
            titles[key] = {'n': c['name'], 't': [i['t'] for i in c['items']]}
    for l in data['lessons']:
        for c in l['courses']:
            key = 'c%d' % c['id']
            dump('lists/%s.json' % key, {'name': c['name'], 'items': c['items']})
            titles[key] = {'n': c['name'], 't': [i['t'] for i in c['items']]}
    khutba = None
    for g in data['audio']:
        for c in g['cats']:
            if c['id'] == 6 and c['items']:
                khutba = max(c['items'], key=lambda i: i['id'])
    index = {
        'v': 2, 'updated': data['updated'], 'khutba': khutba,
        'audio': [{'group': g['group'], 'cats': [{'id': c['id'], 'key': 's%d' % c['id'], 'name': c['name'], 'n': len(c['items'])}
                                                 for c in g['cats']]} for g in data['audio']],
        'lessons': [{'id': l['id'], 'name': l['name'],
                     'courses': [{'id': c['id'], 'key': 'c%d' % c['id'], 'name': c['name'], 'n': len(c['items'])}
                                 for c in l['courses']]} for l in data['lessons']],
        'books': data['books'],
        'bio': bio,
        'docs': [{'id': d['id'], 'name': d['name'], 'n': len(d['items'])} for d in docs],
    }
    dump('index.json', index)
    if docs:
        dump('docs.json', docs)
    dump('titles.json', titles)
    dump('texts.json', data['texts'])
    old = os.path.join(out, 'site.json')
    if os.path.exists(old):
        os.remove(old)
    return 0


if __name__ == '__main__':
    sys.exit(main())
