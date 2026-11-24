import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../screens/book_reader_screen.dart';
import '../theme.dart';
import 'common.dart' show openUrl;

/// The sheikh's book a question was taken from, if it is in the library.
Book? sourceBook(String id) => id.isEmpty ? null : Repository.instance.books.where((b) => b.id == id).firstOrNull;

void openSourceBook(BuildContext context, Book b) => openBook(context, b);

/// Every book button goes through here. In the app the book opens in the
/// reader (kept on the phone); on the website it opens in Google's viewer,
/// because a browser may not download the file from Drive directly.
Future<void> openBook(BuildContext context, Book b, {int? startPage}) async {
  if (kIsWeb) {
    // A book of the sheikh's site is read here, inside the website.
    if (b.url.isNotEmpty) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => WebBookScreen(book: b)));
    } else {
      openUrl(context, b.previewUrl);
    }
    return;
  }
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookReaderScreen(book: b, startPage: startPage)));
}

/// The book's pages on the website, without leaving it.
class WebBookScreen extends StatefulWidget {
  final Book book;
  const WebBookScreen({super.key, required this.book});

  @override
  State<WebBookScreen> createState() => _WebBookScreenState();
}

class _WebBookScreenState extends State<WebBookScreen> {
  int _page = 0, _pages = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          actions: [
            if (_pages > 0)
              Center(
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 14),
                  child: Text('$_page / $_pages', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
        body: PdfViewer.uri(
          Uri.parse(widget.book.url),
          params: PdfViewerParams(
            loadingBannerBuilder: (context, bytesDownloaded, totalBytes) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(
                    value: totalBytes != null && totalBytes > 0 ? bytesDownloaded / totalBytes : null, color: kGold),
                const SizedBox(height: 14),
                const Text('جارٍ فتح الكتاب…'),
              ]),
            ),
            errorBannerBuilder: (context, error, stackTrace, documentRef) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('تعذّر فتح الكتاب الآن.\nتأكد من اتصالك بالإنترنت ثم أعد المحاولة.',
                    textAlign: TextAlign.center, style: TextStyle(height: 1.8)),
              ),
            ),
            onViewerReady: (document, controller) {
              if (mounted) setState(() => _pages = document.pages.length);
            },
            onPageChanged: (page) {
              if (page != null && mounted) setState(() => _page = page);
            },
          ),
        ),
      );
}

/// «تصفّح الكتاب الذي أُخذ منه السؤال»: big and gold after a wrong answer,
/// a quiet outline otherwise.
class SourceBookButton extends StatelessWidget {
  final String bookId;
  final bool strong;
  const SourceBookButton({super.key, required this.bookId, this.strong = false});

  @override
  Widget build(BuildContext context) {
    final b = sourceBook(bookId);
    if (b == null) return const SizedBox.shrink();
    final label = Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(strong ? 'تصفّح الكتاب الذي أُخذ منه السؤال' : 'الكتاب الذي أُخذ منه السؤال',
          style: const TextStyle(fontWeight: FontWeight.bold)),
      Text(b.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
    ]);
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: strong
          ? FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: kGold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                alignment: AlignmentDirectional.centerStart,
              ),
              icon: const Icon(Icons.menu_book, size: 26),
              label: label,
              onPressed: () => openSourceBook(context, b),
            )
          : OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                alignment: AlignmentDirectional.centerStart,
              ),
              icon: const Icon(Icons.menu_book_outlined),
              label: label,
              onPressed: () => openSourceBook(context, b),
            ),
    );
  }
}
