import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/services/family_exports_service.dart';

const _pending = '{"id":"e1","status":"pending",'
    '"filename":"sure_export_20261110_120000.zip","downloadable":false,'
    '"download_path":null,"file":{"attached":false,"byte_size":null,'
    '"content_type":null},"created_at":"2026-11-10T12:00:00Z",'
    '"updated_at":"2026-11-10T12:00:00Z"}';

const _completed = '{"id":"e2","status":"completed",'
    '"filename":"sure_export_20261109_080000.zip","downloadable":true,'
    '"download_path":"/api/v1/family_exports/e2/download",'
    '"file":{"attached":true,"byte_size":2048,"content_type":"application/zip"},'
    '"created_at":"2026-11-09T08:00:00Z","updated_at":"2026-11-09T08:01:00Z"}';

void main() {
  test('list parses data', () async {
    final service = FamilyExportsService(
      client: MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/family_exports');
        expect(request.headers['Authorization'], 'Bearer token');
        return http.Response(
            '{"data":[$_pending,$_completed],"meta":{"page":1,"per_page":25,'
            '"total_count":2,"total_pages":1}}',
            200);
      }),
    );
    final result = await service.list(accessToken: 'token');
    final exports = result['exports'] as List<FamilyExport>;
    expect(exports.length, 2);
    expect(exports.first.inProgress, true);
    expect(exports.last.downloadable, true);
    expect(exports.last.byteSize, 2048);
  });

  test('create posts with no body and accepts 202', () async {
    final service = FamilyExportsService(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/family_exports');
        expect(request.body, isEmpty);
        return http.Response('{"data":$_pending}', 202);
      }),
    );
    final result = await service.create(accessToken: 'token');
    expect((result['export'] as FamilyExport).id, 'e1');
  });

  test('get polls one export', () async {
    final service = FamilyExportsService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/family_exports/e2');
        return http.Response('{"data":$_completed}', 200);
      }),
    );
    final result = await service.get(accessToken: 'token', id: 'e2');
    expect((result['export'] as FamilyExport).status, 'completed');
  });

  test('a non-admin sees the server message', () async {
    final service = FamilyExportsService(
      client: MockClient((_) async => http.Response(
          '{"error":"forbidden","message":"Family exports require a family admin"}',
          403)),
    );
    final result = await service.list(accessToken: 'token');
    expect(result['error'], 'Family exports require a family admin');
    expect(result['status'], 403);
  });

  test('401 is unauthorized', () async {
    final service = FamilyExportsService(
        client: MockClient((_) async => http.Response('', 401)));
    expect((await service.create(accessToken: 'token'))['error'], 'unauthorized');
    expect((await service.list(accessToken: 'token'))['error'], 'unauthorized');
    final download = await service.download(
        accessToken: 'token', id: 'e2', fallbackFilename: 'x.zip');
    expect(download['error'], 'unauthorized');
  });

  group('download', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('exports_test'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('streams bytes to a file named by Content-Disposition', () async {
      final bytes = List<int>.generate(5000, (i) => i % 256);
      final service = FamilyExportsService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/family_exports/e2/download');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response.bytes(bytes, 200, headers: {
            'content-disposition': 'attachment; '
                'filename="sure_export_20261109_080000.zip"; '
                "filename*=UTF-8''sure_export_20261109_080000.zip",
          });
        }),
      );
      final result = await service.download(
        accessToken: 'token',
        id: 'e2',
        fallbackFilename: 'fallback.zip',
        directory: dir,
      );
      final file = result['file'] as File;
      expect(file.path, endsWith('/sure_export_20261109_080000.zip'));
      expect(file.readAsBytesSync(), bytes);
    });

    test('409 when not ready shows the server message', () async {
      final service = FamilyExportsService(
        client: MockClient((_) async => http.Response(
            '{"error":"export_not_ready","message":"Export is not ready for download"}',
            409)),
      );
      final result = await service.download(
          accessToken: 'token', id: 'e1', fallbackFilename: 'x.zip', directory: dir);
      expect(result['error'], 'Export is not ready for download');
    });
  });

  group('filenameFromContentDisposition', () {
    test('prefers filename*', () {
      expect(
        filenameFromContentDisposition(
            "attachment; filename=\"a.zip\"; filename*=UTF-8''r%C3%A4kna.zip"),
        'räkna.zip',
      );
    });
    test('reads plain and unquoted forms', () {
      expect(filenameFromContentDisposition('attachment; filename="b.zip"'), 'b.zip');
      expect(filenameFromContentDisposition('attachment; filename=c.zip'), 'c.zip');
    });
    test('drops directories and rejects empty names', () {
      expect(filenameFromContentDisposition('attachment; filename="../../x.zip"'), 'x.zip');
      expect(filenameFromContentDisposition('attachment; filename=".."'), isNull);
      expect(filenameFromContentDisposition('attachment'), isNull);
      expect(filenameFromContentDisposition(null), isNull);
    });
  });
}
