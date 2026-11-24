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
    ('الردود العلمية', [11, 12, 13, 14, 15, 16, 18]),
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
]


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
        return out
    return f


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
            if len(text) < 40:
                continue
            d = re.search(r'float-start">\s*(\d{4}-\d\d-\d\d)', page)
            data['texts'].append({'id': '%s-%d' % (kind, it['id']), 'type': typ, 'section': section, 'title': it['t'],
                                  'text': text, 'date': d.group(1) if d else '', 'audio': it['audio'],
                                  'source': '%s/%s/%d' % (BASE, kind, it['id'])})
            n += 1
            time.sleep(.2)
        print('texts', section, n)

    n_audio = sum(len(c['items']) for g in data['audio'] for c in g['cats'])
    n_less = sum(len(c['items']) for l in data['lessons'] for c in l['courses'])
    print('audio', n_audio, 'lesson files', n_less)
    if n_audio + n_less == 0 and not data['books']:
        print('nothing read; keeping the old file')
        return 1
    with open(os.path.join(out, 'site.json'), 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, separators=(',', ':'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
