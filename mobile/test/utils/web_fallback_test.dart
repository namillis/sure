import 'package:flutter_test/flutter_test.dart';
import 'package:sure_mobile/utils/web_fallback.dart';

void main() {
  group('webFallbackUri', () {
    test('joins the base URL and path', () {
      expect(webFallbackUri('https://app.sure.am', '/goals').toString(),
          'https://app.sure.am/goals');
    });

    test('tolerates a trailing slash and a missing leading slash', () {
      expect(webFallbackUri('https://app.sure.am/', 'bills').toString(),
          'https://app.sure.am/bills');
    });

    test('keeps a sub-path, a port and the query', () {
      expect(
        webFallbackUri('http://localhost:3000/sure/', '/imports?tab=new')
            .toString(),
        'http://localhost:3000/sure/imports?tab=new',
      );
    });
  });

  group('staysInAppWebView', () {
    const base = 'https://app.sure.am';

    test('keeps pages on the server host in-app', () {
      expect(staysInAppWebView(Uri.parse('https://app.sure.am/rules'), base),
          isTrue);
      expect(staysInAppWebView(Uri.parse('https://APP.sure.am/x'), base),
          isTrue);
      expect(staysInAppWebView(Uri.parse('about:blank'), base), isTrue);
    });

    test('sends other hosts and non-web schemes out', () {
      expect(staysInAppWebView(Uri.parse('https://github.com/x'), base),
          isFalse);
      expect(
          staysInAppWebView(Uri.parse('https://evil.app.sure.am.example'), base),
          isFalse);
      expect(staysInAppWebView(Uri.parse('mailto:a@b.c'), base), isFalse);
      expect(staysInAppWebView(Uri.parse('https://x.y'), ''), isFalse);
    });
  });

  test('isIgnorableWebError skips cancelled and policy-interrupted loads', () {
    expect(isIgnorableWebError(-999), isTrue);
    expect(isIgnorableWebError(102), isTrue);
    expect(isIgnorableWebError(-1009), isFalse);
  });
}
