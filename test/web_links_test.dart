import 'package:atomic_notes/utility/web_links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only https pages open in the browser', () {
    expect(WebLinks.isWeb(WebLinks.support), isTrue);
    expect(WebLinks.isWeb(' https://example.com/page '), isTrue);
    expect(WebLinks.isWeb('http://example.com'), isFalse, reason: 'no plain http');
    expect(WebLinks.isWeb('/energypage'), isFalse, reason: 'in-app route');
    expect(WebLinks.isWeb('javascript:alert(1)'), isFalse);
    expect(WebLinks.isWeb('intent://scan/#Intent;scheme=zxing;end'), isFalse);
    expect(WebLinks.isWeb('https://'), isFalse, reason: 'no host');
    expect(WebLinks.isWeb(''), isFalse);
  });

  test('the support page lives on the Atomic Notes website', () {
    expect(WebLinks.support,
        'https://atomic-notes-community.vercel.app/support-atomic-notes');
  });
}
