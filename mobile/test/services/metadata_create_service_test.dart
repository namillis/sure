import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/models/merchant.dart';
import 'package:sure_mobile/models/transaction_tag.dart';
import 'package:sure_mobile/services/metadata_create_service.dart';

void main() {
  group('MetadataCreateService.createTag', () {
    test('posts the name and parses the created tag', () async {
      final service = MetadataCreateService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/tags');
          expect(request.headers['Authorization'], 'Bearer token');
          expect(jsonDecode(request.body), {
            'tag': {'name': 'Travel'},
          });
          return http.Response(
            '{"id":"tag_9","name":"Travel","color":"#3b82f6",'
            '"created_at":"2026-11-10T00:00:00Z","updated_at":"2026-11-10T00:00:00Z"}',
            201,
          );
        }),
      );

      final result =
          await service.createTag(accessToken: 'token', name: '  Travel ');

      expect(result['success'], true);
      final tag = result['tag'] as TransactionTag;
      expect(tag.id, 'tag_9');
      expect(tag.color, '#3b82f6');
    });

    test('shows the server error for a duplicate', () async {
      final service = MetadataCreateService(
        client: MockClient((_) async => http.Response(
              '{"error":"Name has already been taken"}',
              422,
            )),
      );

      final result = await service.createTag(accessToken: 'token', name: 'Travel');

      expect(result['success'], false);
      expect(result['error'], 'Name has already been taken');
    });

    test('returns unauthorized on 401', () async {
      final service = MetadataCreateService(
        client: MockClient((_) async => http.Response('', 401)),
      );

      final result = await service.createTag(accessToken: 'token', name: 'x');

      expect(result['error'], 'unauthorized');
    });
  });

  group('MetadataCreateService.createCategory', () {
    test('posts the name and parses the created category', () async {
      final service = MetadataCreateService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/categories');
          expect(jsonDecode(request.body), {
            'category': {'name': 'Pets'},
          });
          return http.Response(
            '{"id":"cat_9","name":"Pets","color":"#e99537","icon":"paw-print",'
            '"parent":null,"subcategories_count":0,'
            '"created_at":"2026-11-10T00:00:00Z","updated_at":"2026-11-10T00:00:00Z"}',
            201,
          );
        }),
      );

      final result =
          await service.createCategory(accessToken: 'token', name: 'Pets');

      expect(result['success'], true);
      expect((result['category'] as Category).id, 'cat_9');
    });

    test('shows why a locked family refuses it', () async {
      final service = MetadataCreateService(
        client: MockClient((_) async => http.Response(
              '{"error":"unprocessable_entity",'
              '"message":"Categories are locked. Unlock them to add a new category."}',
              422,
            )),
      );

      final result =
          await service.createCategory(accessToken: 'token', name: 'Pets');

      expect(result['success'], false);
      expect(result['error'], contains('Categories are locked'));
    });
  });

  group('MetadataCreateService.createMerchant', () {
    test('uploads a one-row CSV as multipart and returns the merchant',
        () async {
      final service = MetadataCreateService(
        client: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/api/v1/merchants');
          expect(request.headers['Authorization'], 'Bearer token');
          final contentType = request.headers['Content-Type']!;
          expect(contentType, startsWith('multipart/form-data; boundary='));
          final boundary = contentType.split('boundary=').last;
          final body = request.body;
          expect(body, startsWith('--$boundary\r\n'));
          expect(
            body,
            contains('Content-Disposition: form-data; name="file"; '
                'filename="merchant.csv"\r\n'),
          );
          expect(body, contains('Content-Type: text/csv\r\n'));
          // Quotes are doubled inside the quoted CSV field.
          expect(body, contains('name\n"Joe\'s ""Diner"", Inc"\n'));
          expect(body, endsWith('--$boundary--\r\n'));
          return http.Response(
            '{"imported":1,"skipped":0,"merchants":[{"id":"m_9",'
            '"name":"Joe\'s \\"Diner\\", Inc","type":"FamilyMerchant"}]}',
            201,
          );
        }),
      );

      final result = await service.createMerchant(
        accessToken: 'token',
        name: ' Joe\'s "Diner", Inc ',
      );

      expect(result['success'], true);
      final merchant = result['merchant'] as Merchant;
      expect(merchant.id, 'm_9');
      expect(merchant.type, 'FamilyMerchant');
    });

    test('finds the existing merchant when the import skips it', () async {
      final requests = <String>[];
      final service = MetadataCreateService(
        client: MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'POST') {
            return http.Response(
              '{"imported":0,"skipped":1,"merchants":[]}',
              201,
            );
          }
          return http.Response(
            '[{"id":"m_1","name":"Other"},{"id":"m_2","name":"Cafe"}]',
            200,
          );
        }),
      );

      final result =
          await service.createMerchant(accessToken: 'token', name: 'Cafe');

      expect(requests, ['POST /api/v1/merchants', 'GET /api/v1/merchants']);
      expect(result['success'], true);
      expect((result['merchant'] as Merchant).id, 'm_2');
    });

    test('shows the server message on a rejected upload', () async {
      final service = MetadataCreateService(
        client: MockClient((_) async => http.Response(
              '{"error":"invalid_file_type",'
              '"message":"Invalid file type. Please upload a CSV file."}',
              422,
            )),
      );

      final result =
          await service.createMerchant(accessToken: 'token', name: 'Cafe');

      expect(result['success'], false);
      expect(result['error'], 'Invalid file type. Please upload a CSV file.');
    });

    test('returns unauthorized on 401', () async {
      final service = MetadataCreateService(
        client: MockClient((_) async => http.Response('', 401)),
      );

      final result =
          await service.createMerchant(accessToken: 'token', name: 'Cafe');

      expect(result['error'], 'unauthorized');
    });
  });
}
