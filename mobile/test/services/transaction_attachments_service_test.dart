import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/transaction.dart';
import 'package:sure_mobile/models/transaction_attachment.dart';
import 'package:sure_mobile/services/api_config.dart';
import 'package:sure_mobile/services/transaction_attachments_service.dart';

Uint8List _bytes(List<int> head) => Uint8List.fromList([...head, 0, 0, 0, 0]);

TransactionAttachment _attachment({String url = ''}) => TransactionAttachment(
      id: 'att_1',
      filename: 'r.jpg',
      contentType: 'image/jpeg',
      byteSize: 3,
      url: url,
    );

void main() {
  setUp(() {
    ApiConfig.clearApiKeyAuth();
    ApiConfig.setBaseUrl('https://money.example.com');
  });
  tearDown(() => ApiConfig.setBaseUrl(ApiConfig.defaultBaseUrl));

  group('attachmentContentType', () {
    test('detects the allowed types from their bytes', () {
      expect(attachmentContentType(_bytes([0xFF, 0xD8, 0xFF, 0xE0])),
          'image/jpeg');
      expect(
          attachmentContentType(
              _bytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])),
          'image/png');
      expect(attachmentContentType(_bytes(ascii.encode('GIF89a'))), 'image/gif');
      expect(attachmentContentType(_bytes(ascii.encode('RIFF\x00\x00\x00\x00WEBP'))),
          'image/webp');
      expect(attachmentContentType(_bytes(ascii.encode('%PDF-1.7'))),
          'application/pdf');
    });

    test('refuses HEIC and anything else', () {
      expect(
          attachmentContentType(
              _bytes([0, 0, 0, 0x18, ...ascii.encode('ftypheic')])),
          isNull);
      expect(attachmentContentType(_bytes(ascii.encode('hello'))), isNull);
      expect(attachmentContentType(Uint8List(0)), isNull);
    });
  });

  test('attachmentFilename matches the extension to the real type', () {
    expect(attachmentFilename('IMG_1.HEIC', 'image/jpeg'), 'IMG_1.jpg');
    expect(attachmentFilename('scan.jpeg', 'image/jpeg'), 'scan.jpeg');
    expect(attachmentFilename('bill.pdf', 'application/pdf'), 'bill.pdf');
    expect(attachmentFilename('', 'image/png'), 'receipt.png');
  });

  test('Transaction parses attachments and the account type', () {
    final t = Transaction.fromJson({
      'id': 't1',
      'name': 'Coffee',
      'date': '2026-11-06',
      'amount': '\$4.50',
      'currency': 'USD',
      'account': {'id': 'a1', 'name': 'Brokerage', 'account_type': 'investment'},
      'attachments': [
        {
          'id': 'att_1',
          'filename': 'r.jpg',
          'content_type': 'image/jpeg',
          'byte_size': 1200,
          'created_at': '2026-11-06T10:00:00Z',
          'url': 'https://money.example.com/api/v1/attachments/att_1',
        },
        {'filename': 'no id'},
      ],
    });
    expect(t.accountType, 'investment');
    expect(t.attachments, hasLength(1));
    expect(t.attachments!.single.isImage, isTrue);
    expect(t.attachments!.single.byteSize, 1200);

    final old = Transaction.fromJson({'id': 't2', 'name': 'x'});
    expect(old.attachments, isNull);
    expect(old.accountType, isNull);
  });

  test('fileUri sends credentials only to the signed-in server', () {
    final service = TransactionAttachmentsService(
        client: MockClient((_) async => http.Response('', 200)));
    expect(
        service
            .fileUri(_attachment(
                url: 'https://money.example.com/api/v1/attachments/att_1'))
            .toString(),
        'https://money.example.com/api/v1/attachments/att_1');
    expect(
        service
            .fileUri(_attachment(url: 'https://evil.example/api/v1/attachments/x'))
            .toString(),
        'https://money.example.com/api/v1/attachments/att_1');
  });

  test('upload posts multipart file and parses the attachment', () async {
    late http.BaseRequest seen;
    String body = '';
    final service = TransactionAttachmentsService(
      client: MockClient((request) async {
        seen = request;
        body = latin1.decode(request.bodyBytes);
        return http.Response(
          jsonEncode({
            'id': 'att_9',
            'filename': 'r.jpg',
            'content_type': 'image/jpeg',
            'byte_size': 4,
            'url': 'https://money.example.com/api/v1/attachments/att_9',
          }),
          201,
        );
      }),
    );
    final result = await service.upload(
      accessToken: 'tok',
      transactionId: 't1',
      bytes: [0xFF, 0xD8, 0xFF, 0xE0],
      filename: 'r.jpg',
      contentType: 'image/jpeg',
    );
    expect(result['success'], isTrue);
    expect((result['attachment'] as TransactionAttachment).id, 'att_9');
    expect(seen.method, 'POST');
    expect(seen.url.path, '/api/v1/transactions/t1/attachments');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(body, contains('name="file"; filename="r.jpg"'));
    expect(body, contains('content-type: image/jpeg'));
  });

  test('upload and delete surface the server message', () async {
    final service = TransactionAttachmentsService(
      client: MockClient((request) async => request.method == 'DELETE'
          ? http.Response(
              jsonEncode({
                'error': 'forbidden',
                'message': 'You do not have permission',
              }),
              403)
          : http.Response(
              jsonEncode({
                'error': 'validation_failed',
                'message': 'too big',
                'errors': ['File is too big'],
              }),
              422)),
    );
    final upload = await service.upload(
      accessToken: 'tok',
      transactionId: 't1',
      bytes: [1],
      filename: 'a.pdf',
      contentType: 'application/pdf',
    );
    expect(upload['success'], isFalse);
    expect(upload['error'], 'File is too big');
    final delete = await service.delete(
        accessToken: 'tok', transactionId: 't1', attachmentId: 'att_1');
    expect(delete['status'], 403);
    expect(delete['error'], 'You do not have permission');
  });

  test('download fetches bytes with the auth headers', () async {
    late http.Request seen;
    final service = TransactionAttachmentsService(
      client: MockClient((request) async {
        seen = request;
        return http.Response.bytes([1, 2, 3], 200);
      }),
    );
    final result = await service.download(
      accessToken: 'tok',
      attachment: _attachment(
          url: 'https://money.example.com/api/v1/attachments/att_1'),
    );
    expect(result['bytes'], [1, 2, 3]);
    expect(seen.headers['Authorization'], 'Bearer tok');
  });
}
