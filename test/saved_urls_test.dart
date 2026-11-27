import 'package:aloud/features/web_import/saved_urls.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SavedUrls', () {
    test('remembers what was added', () {
      final s = SavedUrls()..add(Uri.parse('https://site.com/book/ch-1'));
      expect(s.contains(Uri.parse('https://site.com/book/ch-1')), isTrue);
      expect(s.contains(Uri.parse('https://site.com/book/ch-2')), isFalse);
    });

    test('ignores the fragment and a trailing slash', () {
      final s = SavedUrls()..add(Uri.parse('https://site.com/book/ch-1/'));
      expect(s.contains(Uri.parse('https://site.com/book/ch-1#comments')), isTrue);
    });

    test('query strings still tell pages apart', () {
      final s = SavedUrls()..add(Uri.parse('https://site.com/read?chapter=1'));
      expect(s.contains(Uri.parse('https://site.com/read?chapter=2')), isFalse);
    });

    test('can be seeded and cleared', () {
      final s = SavedUrls([Uri.parse('https://site.com/a')]);
      expect(s.contains(Uri.parse('https://site.com/a')), isTrue);
      s.clear();
      expect(s.contains(Uri.parse('https://site.com/a')), isFalse);
    });
  });
}
