import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/category.dart';
import 'package:sure_mobile/models/merchant.dart';
import 'package:sure_mobile/models/transaction_tag.dart';
import 'package:sure_mobile/services/metadata_create_service.dart';
import 'package:sure_mobile/services/metadata_manage_service.dart';

String _category(String id, String name, {String? parentId, String? parentName}) =>
    jsonEncode({
      'id': id,
      'name': name,
      'color': '#e99537',
      'icon': 'shapes',
      'parent': parentId == null ? null : {'id': parentId, 'name': parentName},
      'subcategories_count': 0,
      'created_at': '2026-11-10T00:00:00Z',
      'updated_at': '2026-11-10T00:00:00Z',
    });

void main() {
  group('listCategories', () {
    test('walks pages and builds the hierarchy', () async {
      final pages = <String>[];
      final service = MetadataManageService(
        client: MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/categories');
          expect(request.url.queryParameters['per_page'], '100');
          final page = request.url.queryParameters['page']!;
          pages.add(page);
          final items = page == '1'
              ? [_category('c1', 'Food'), _category('c2', 'Groceries', parentId: 'c1', parentName: 'Food')]
              : [_category('c3', 'Travel'), _category('c4', 'Orphan', parentId: 'gone', parentName: 'Gone')];
          return http.Response(
            '{"categories":[${items.join(',')}],'
            '"pagination":{"page":$page,"per_page":100,"total_count":4,"total_pages":2}}',
            200,
          );
        }),
      );

      final result = await service.listCategories(accessToken: 'token');

      expect(pages, ['1', '2']);
      expect(result['success'], true);
      final categories = result['categories'] as List<Category>;
      expect(categories.length, 4);
      final tree = buildCategoryTree(categories);
      expect(tree.map((n) => n.category.name), ['Food', 'Travel', 'Orphan']);
      expect(tree.first.children.single.name, 'Groceries');

      final filtered = filterCategoryTree(tree, 'groc');
      expect(filtered.single.category.name, 'Food');
      expect(filtered.single.children.single.name, 'Groceries');
      expect(filterCategoryTree(tree, 'food').single.children.length, 1);
    });

    test('returns unauthorized on 401', () async {
      final service = MetadataManageService(
          client: MockClient((_) async => http.Response('', 401)));
      final result = await service.listCategories(accessToken: 'token');
      expect(result['error'], 'unauthorized');
    });
  });

  group('tags', () {
    test('lists tags', () async {
      final service = MetadataManageService(
        client: MockClient((request) async {
          expect(request.url.path, '/api/v1/tags');
          expect(request.headers['Authorization'], 'Bearer token');
          return http.Response(
              '[{"id":"t1","name":"Trip","color":"#4da568"},{"id":"","name":"bad"}]',
              200);
        }),
      );
      final result = await service.listTags(accessToken: 'token');
      final tags = result['tags'] as List<TransactionTag>;
      expect(tags.single.color, '#4da568');
    });

    test('updates name and color with PATCH', () async {
      final service = MetadataManageService(
        client: MockClient((request) async {
          expect(request.method, 'PATCH');
          expect(request.url.path, '/api/v1/tags/t1');
          expect(jsonDecode(request.body), {
            'tag': {'name': 'Trips', 'color': '#6471eb'},
          });
          return http.Response('{"id":"t1","name":"Trips","color":"#6471eb"}', 200);
        }),
      );
      final result = await service.updateTag(
          accessToken: 'token', id: 't1', name: ' Trips ', color: '#6471eb');
      expect((result['tag'] as TransactionTag).name, 'Trips');
    });

    test('update shows the server validation error', () async {
      final service = MetadataManageService(
        client: MockClient((_) async =>
            http.Response('{"error":"Name has already been taken"}', 422)),
      );
      final result =
          await service.updateTag(accessToken: 'token', id: 't1', name: 'x');
      expect(result['success'], false);
      expect(result['error'], 'Name has already been taken');
    });

    test('deletes with DELETE and accepts 204', () async {
      final service = MetadataManageService(
        client: MockClient((request) async {
          expect(request.method, 'DELETE');
          expect(request.url.path, '/api/v1/tags/t1');
          return http.Response('', 204);
        }),
      );
      final result = await service.deleteTag(accessToken: 'token', id: 't1');
      expect(result['success'], true);
    });

    test('delete returns unauthorized on 401', () async {
      final service = MetadataManageService(
          client: MockClient((_) async => http.Response('', 401)));
      final result = await service.deleteTag(accessToken: 'token', id: 't1');
      expect(result['error'], 'unauthorized');
    });
  });

  test('lists merchants', () async {
    final service = MetadataManageService(
      client: MockClient((request) async {
        expect(request.url.path, '/api/v1/merchants');
        return http.Response(
            '[{"id":"m1","name":"Cafe","type":"FamilyMerchant"},'
            '{"id":"m2","name":"Amazon","type":"ProviderMerchant"}]',
            200);
      }),
    );
    final result = await service.listMerchants(accessToken: 'token');
    final merchants = result['merchants'] as List<Merchant>;
    expect(merchants.map((m) => m.type), ['FamilyMerchant', 'ProviderMerchant']);
  });

  group('MetadataCreateService additions', () {
    test('createTag sends the chosen color', () async {
      final service = MetadataCreateService(
        client: MockClient((request) async {
          expect(jsonDecode(request.body), {
            'tag': {'name': 'Trip', 'color': '#4da568'},
          });
          return http.Response('{"id":"t1","name":"Trip","color":"#4da568"}', 201);
        }),
      );
      final result = await service.createTag(
          accessToken: 'token', name: 'Trip', color: '#4da568');
      expect(result['success'], true);
    });

    test('createCategory sends color and parent_id', () async {
      final service = MetadataCreateService(
        client: MockClient((request) async {
          expect(jsonDecode(request.body), {
            'category': {'name': 'Coffee', 'color': '#805dee', 'parent_id': 'c1'},
          });
          return http.Response(
              _category('c9', 'Coffee', parentId: 'c1', parentName: 'Food'), 201);
        }),
      );
      final result = await service.createCategory(
          accessToken: 'token', name: 'Coffee', color: '#805dee', parentId: 'c1');
      expect((result['category'] as Category).parent?.id, 'c1');
    });

    test('createMerchant adds color and website_url columns', () async {
      final service = MetadataCreateService(
        client: MockClient((request) async {
          expect(
            request.body,
            contains('name,color,website_url\n'
                '"Cafe, Inc","#db5a54","https://cafe.example"\n'),
          );
          return http.Response(
              '{"imported":1,"skipped":0,"merchants":[{"id":"m9","name":"Cafe, Inc"}]}',
              201);
        }),
      );
      final result = await service.createMerchant(
        accessToken: 'token',
        name: 'Cafe, Inc',
        color: '#db5a54',
        websiteUrl: ' https://cafe.example ',
      );
      expect((result['merchant'] as Merchant).id, 'm9');
      expect(result['existing'], isNull);
    });
  });
}
