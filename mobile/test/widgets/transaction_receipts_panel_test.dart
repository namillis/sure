import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:sure_mobile/l10n/app_localizations.dart';
import 'package:sure_mobile/models/transaction.dart';
import 'package:sure_mobile/providers/auth_provider.dart';
import 'package:sure_mobile/services/api_config.dart';
import 'package:sure_mobile/services/file_pick.dart';
import 'package:sure_mobile/services/transaction_attachments_service.dart';
import 'package:sure_mobile/theme/sure_theme.dart';
import 'package:sure_mobile/widgets/transaction_receipts_panel.dart';

class _FakeAuth extends ChangeNotifier implements AuthProvider {
  int logouts = 0;
  @override
  Future<String?> getValidAccessToken() async => 'token';
  @override
  Future<void> logout() async => logouts++;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');
final _jpeg = [0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0];

Map<String, dynamic> _att(String id, {String type = 'image/png'}) => {
      'id': id,
      'filename': type == 'application/pdf' ? '$id.pdf' : '$id.png',
      'content_type': type,
      'byte_size': 100,
      'created_at': '2026-11-06T10:00:00Z',
      'url': 'https://money.example.com/api/v1/attachments/$id',
    };

Transaction _txn(List<Map<String, dynamic>> attachments) => Transaction.fromJson({
      'id': 'txn_1',
      'name': 'Lunch',
      'date': '2026-11-06',
      'amount': '\$12.00',
      'currency': 'USD',
      'account': {'id': 'a1', 'name': 'Checking'},
      'attachments': attachments,
    });

class _Harness {
  final requests = <http.Request>[];
  final picks = <ReceiptSource>[];
  final opened = <(String name, String type, bool existed)>[];
  http.Response Function(http.Request)? onUpload;
  http.Response Function(http.Request)? onDelete;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  List<Map<String, dynamic>> attachments = const [],
  bool canDelete = true,
  PickedFileData? picked,
  double width = 390,
  Brightness brightness = Brightness.light,
  void Function(_Harness h)? configure,
}) async {
  final h = _Harness();
  configure?.call(h);
  final client = MockClient((request) async {
    h.requests.add(request);
    if (request.method == 'POST') {
      return h.onUpload?.call(request) ??
          http.Response(jsonEncode(_att('att_new', type: 'image/jpeg')), 201);
    }
    if (request.method == 'DELETE') {
      return h.onDelete?.call(request) ?? http.Response('', 204);
    }
    return http.Response.bytes(_png, 200);
  });
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthProvider>.value(
      value: _FakeAuth(),
      child: MaterialApp(
        theme: brightness == Brightness.dark ? SureTheme.dark : SureTheme.light,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: TransactionReceiptsPanel(
              transaction: _txn(attachments),
              online: true,
              canDelete: canDelete,
              service: TransactionAttachmentsService(client: client),
              pick: (source) async {
                h.picks.add(source);
                return picked;
              },
              openFile: (file, type, origin) async {
                h.opened.add((
                  file.uri.pathSegments.last,
                  type,
                  file.existsSync(),
                ));
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return h;
}

Iterable<http.Request> _writes(_Harness h) =>
    h.requests.where((r) => r.method != 'GET');

void main() {
  setUp(() {
    ApiConfig.clearApiKeyAuth();
    ApiConfig.setBaseUrl('https://money.example.com');
  });
  tearDown(() => ApiConfig.setBaseUrl(ApiConfig.defaultBaseUrl));

  testWidgets('loads image thumbnails with auth; PDFs show a file icon',
      (tester) async {
    final h = await _pump(tester, attachments: [
      _att('img'),
      _att('doc', type: 'application/pdf'),
    ]);
    expect(find.text('Receipts'), findsOneWidget);
    expect(h.requests, hasLength(1));
    expect(h.requests.single.url.path, '/api/v1/attachments/img');
    expect(h.requests.single.headers['Authorization'], 'Bearer token');
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('receipt-img')),
            matching: find.byType(Image)),
        findsOneWidget);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('receipt-doc')),
            matching: find.byType(Image)),
        findsNothing);
  });

  testWidgets('tapping a PDF downloads it and hands it to the system',
      (tester) async {
    final h = await _pump(tester,
        attachments: [_att('doc', type: 'application/pdf')]);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('receipt-doc')));
      for (var i = 0; i < 50 && h.opened.isEmpty; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(h.requests.single.url.path, '/api/v1/attachments/doc');
    expect(h.opened, [('doc.pdf', 'application/pdf', true)]);
  });

  testWidgets('choose photo uploads a JPEG and shows it', (tester) async {
    final h = await _pump(tester,
        picked: PickedFileData.bytes('IMG_1.HEIC', _jpeg));
    await tester.tap(find.byKey(const ValueKey('receipt-add')));
    await tester.pumpAndSettle();
    expect(find.text('Take photo'), findsOneWidget);
    expect(find.text('Choose file'), findsOneWidget);
    await tester.tap(find.text('Choose photo'));
    await tester.pumpAndSettle();
    expect(h.picks, [ReceiptSource.photos]);
    final post = _writes(h).single;
    expect(post.url.path, '/api/v1/transactions/txn_1/attachments');
    final body = latin1.decode(post.bodyBytes);
    expect(body, contains('filename="IMG_1.jpg"'));
    expect(body, contains('content-type: image/jpeg'));
    expect(find.byKey(const ValueKey('receipt-att_new')), findsOneWidget);
    expect(find.text('Receipt added'), findsOneWidget);
  });

  testWidgets('refuses files over 10 MB before uploading', (tester) async {
    final h = await _pump(tester,
        picked: PickedFileData(
          name: 'big.pdf',
          size: 11 * 1024 * 1024,
          read: () => throw StateError('must not read'),
        ));
    await tester.tap(find.byKey(const ValueKey('receipt-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('Files can be at most 10 MB.'), findsOneWidget);
    expect(_writes(h), isEmpty);
  });

  testWidgets('refuses HEIC and other types before uploading', (tester) async {
    final h = await _pump(tester,
        picked: PickedFileData.bytes(
            'IMG.heic', [0, 0, 0, 0x18, ...ascii.encode('ftypheic')]));
    await tester.tap(find.byKey(const ValueKey('receipt-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose file'));
    await tester.pumpAndSettle();
    expect(find.text('Only JPEG, PNG, GIF, WebP and PDF files can be attached.'),
        findsOneWidget);
    expect(_writes(h), isEmpty);
  });

  testWidgets('refuses an 11th attachment without opening the picker',
      (tester) async {
    final h = await _pump(tester, attachments: [
      for (var i = 0; i < 10; i++) _att('d$i', type: 'application/pdf'),
    ]);
    await tester.tap(find.byKey(const ValueKey('receipt-add')));
    await tester.pumpAndSettle();
    expect(find.text('A transaction can have at most 10 attachments.'),
        findsOneWidget);
    expect(find.text('Take photo'), findsNothing);
    expect(h.picks, isEmpty);
  });

  testWidgets('shows the server 422 message', (tester) async {
    await _pump(
      tester,
      picked: PickedFileData.bytes('r.jpg', _jpeg),
      configure: (h) => h.onUpload = (_) => http.Response(
            jsonEncode({
              'error': 'validation_failed',
              'message': 'Attachments is invalid',
              'errors': ['Attachments is invalid'],
            }),
            422,
          ),
    );
    await tester.tap(find.byKey(const ValueKey('receipt-add')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take photo'));
    await tester.pumpAndSettle();
    expect(find.text('Attachments is invalid'), findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-att_new')), findsNothing);
  });

  testWidgets('long-press deletes after a confirm', (tester) async {
    final h = await _pump(tester,
        attachments: [_att('doc', type: 'application/pdf')]);
    await tester.longPress(find.byKey(const ValueKey('receipt-doc')));
    await tester.pumpAndSettle();
    expect(find.text('Delete attachment?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('receiptDeleteConfirm')));
    await tester.pumpAndSettle();
    final delete = _writes(h).single;
    expect(delete.method, 'DELETE');
    expect(delete.url.path, '/api/v1/transactions/txn_1/attachments/doc');
    expect(find.byKey(const ValueKey('receipt-doc')), findsNothing);
    expect(find.text('Attachment deleted'), findsOneWidget);
  });

  testWidgets('without delete permission long-press does nothing',
      (tester) async {
    await _pump(tester,
        canDelete: false, attachments: [_att('doc', type: 'application/pdf')]);
    await tester.longPress(find.byKey(const ValueKey('receipt-doc')));
    await tester.pumpAndSettle();
    expect(find.text('Delete attachment?'), findsNothing);
  });

  testWidgets('a 403 on delete shows the server message and keeps the file',
      (tester) async {
    await _pump(
      tester,
      attachments: [_att('doc', type: 'application/pdf')],
      configure: (h) => h.onDelete = (_) => http.Response(
            jsonEncode({
              'error': 'forbidden',
              'message':
                  "You do not have permission to change this account's attachments",
            }),
            403,
          ),
    );
    await tester.longPress(find.byKey(const ValueKey('receipt-doc')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receiptDeleteConfirm')));
    await tester.pumpAndSettle();
    expect(
        find.text(
            "You do not have permission to change this account's attachments"),
        findsOneWidget);
    expect(find.byKey(const ValueKey('receipt-doc')), findsOneWidget);
  });

  testWidgets('the image viewer deletes and closes', (tester) async {
    final h = await _pump(tester, attachments: [_att('img')]);
    await tester.tap(find.byKey(const ValueKey('receipt-img')));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptViewerScreen), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('receiptViewerDelete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receiptDeleteConfirm')));
    await tester.pumpAndSettle();
    expect(find.byType(ReceiptViewerScreen), findsNothing);
    expect(_writes(h).single.method, 'DELETE');
    expect(find.byKey(const ValueKey('receipt-img')), findsNothing);
  });

  testWidgets('the viewer has no Delete without permission', (tester) async {
    await _pump(tester, canDelete: false, attachments: [_att('img')]);
    await tester.tap(find.byKey(const ValueKey('receipt-img')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('receiptViewerDelete')), findsNothing);
  });

  for (final brightness in [Brightness.light, Brightness.dark]) {
    testWidgets('ten tiles fit at 320 px ($brightness)', (tester) async {
      await _pump(tester, width: 320, brightness: brightness, attachments: [
        for (var i = 0; i < 10; i++)
          _att('f$i', type: i.isEven ? 'image/png' : 'application/pdf'),
      ]);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('receipt-add')), findsOneWidget);
    });
  }
}
