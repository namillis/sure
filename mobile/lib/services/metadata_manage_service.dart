import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/category.dart';
import '../models/merchant.dart';
import '../models/transaction_tag.dart';
import 'api_config.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// The palette the web offers for categories, tags and merchants
/// (`Category::COLORS`, `Tag::COLORS` and `FamilyMerchant::COLORS` on the
/// server are the same list).
const List<String> kMetadataColors = [
  '#e99537',
  '#4da568',
  '#6471eb',
  '#db5a54',
  '#df4e92',
  '#c44fe9',
  '#eb5429',
  '#61c9ea',
  '#805dee',
  '#6ad28a',
];

/// A parent category and its subcategories, in server (alphabetical) order.
class CategoryNode {
  CategoryNode(this.category, [List<Category>? children])
      : children = children ?? [];

  final Category category;
  final List<Category> children;
}

/// Groups a flat category list into parents with their subcategories. A
/// subcategory whose parent isn't in [categories] is shown as a root.
List<CategoryNode> buildCategoryTree(List<Category> categories) {
  final ids = categories.map((c) => c.id).toSet();
  final roots = <CategoryNode>[];
  final byId = <String, CategoryNode>{};
  for (final category in categories) {
    final parentId = category.parent?.id;
    if (parentId == null || !ids.contains(parentId)) {
      final node = CategoryNode(category);
      roots.add(node);
      byId[category.id] = node;
    }
  }
  for (final category in categories) {
    final parentId = category.parent?.id;
    if (parentId != null && byId.containsKey(parentId)) {
      byId[parentId]!.children.add(category);
    }
  }
  return roots;
}

/// Keeps the parents whose name matches [query] (with all their
/// subcategories) and the subcategories that match (under their parent).
List<CategoryNode> filterCategoryTree(List<CategoryNode> tree, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return tree;
  bool matches(Category c) => c.name.toLowerCase().contains(q);
  final result = <CategoryNode>[];
  for (final node in tree) {
    if (matches(node.category)) {
      result.add(node);
    } else {
      final children = node.children.where(matches).toList();
      if (children.isNotEmpty) result.add(CategoryNode(node.category, children));
    }
  }
  return result;
}

/// Lists, updates and deletes the family's categories, tags and merchants for
/// the management screens. Creating goes through `MetadataCreateService`.
///
/// Results are `{'success': bool, ...}` maps, with `'error': 'unauthorized'`
/// on 401.
class MetadataManageService {
  MetadataManageService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  static const _timeout = Duration(seconds: 30);
  static const _perPage = 100;
  static const _maxPages = 20;

  void close() {
    if (_ownsClient) _client.close();
  }

  Map<String, String> _headers(String accessToken) => {
        ...ApiConfig.getAuthHeaders(accessToken),
        'Content-Type': 'application/json',
      };

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: query);

  /// Every category, walking pages of 100. `'categories'` holds a flat
  /// `List<Category>`; group it with [buildCategoryTree].
  Future<Map<String, dynamic>> listCategories({
    required String accessToken,
  }) async {
    const fallback = 'Failed to load categories';
    final categories = <Category>[];
    try {
      var page = 1;
      var totalPages = 1;
      while (page <= totalPages && page <= _maxPages) {
        final response = await _client
            .get(
              _uri('/api/v1/categories', {
                'page': '$page',
                'per_page': '$_perPage',
              }),
              headers: _headers(accessToken),
            )
            .timeout(_timeout);
        if (response.statusCode != 200) return _failure(response, fallback);
        final data = jsonDecode(response.body);
        categories.addAll(extractJsonObjectList(data, key: 'categories')
            .map(Category.fromJson)
            .where((c) => c.id.isNotEmpty));
        final pagination = data is Map ? data['pagination'] : null;
        totalPages = pagination is Map
            ? (pagination['total_pages'] as num?)?.toInt() ?? 1
            : 1;
        page++;
      }
      return {'success': true, 'categories': categories};
    } catch (e) {
      _log('listCategories', e);
      return {'success': false, 'error': fallback};
    }
  }

  /// `GET /api/v1/tags`. `'tags'` holds a `List<TransactionTag>`.
  Future<Map<String, dynamic>> listTags({required String accessToken}) {
    return _getList(
      'listTags',
      path: '/api/v1/tags',
      key: 'tags',
      fromJson: TransactionTag.fromJson,
      isValid: (TransactionTag t) => t.id.isNotEmpty,
      accessToken: accessToken,
      fallback: 'Failed to load tags',
    );
  }

  /// `GET /api/v1/merchants`: family merchants plus provider merchants on
  /// the user's transactions. `'merchants'` holds a `List<Merchant>`.
  Future<Map<String, dynamic>> listMerchants({required String accessToken}) {
    return _getList(
      'listMerchants',
      path: '/api/v1/merchants',
      key: 'merchants',
      fromJson: Merchant.fromJson,
      isValid: (Merchant m) => m.id.isNotEmpty,
      accessToken: accessToken,
      fallback: 'Failed to load merchants',
    );
  }

  /// `PATCH /api/v1/tags/:id` with the fields given. `'tag'` holds the
  /// updated [TransactionTag].
  Future<Map<String, dynamic>> updateTag({
    required String accessToken,
    required String id,
    String? name,
    String? color,
  }) async {
    const fallback = 'Failed to update tag';
    try {
      final response = await _client
          .patch(
            _uri('/api/v1/tags/${Uri.encodeComponent(id)}'),
            headers: _headers(accessToken),
            body: jsonEncode({
              'tag': {
                if (name != null) 'name': name.trim(),
                if (color != null) 'color': color,
              },
            }),
          )
          .timeout(_timeout);
      if (response.statusCode != 200) return _failure(response, fallback);
      return {
        'success': true,
        'tag': TransactionTag.fromJson(
            jsonDecode(response.body) as Map<String, dynamic>),
      };
    } catch (e) {
      _log('updateTag', e);
      return {'success': false, 'error': fallback};
    }
  }

  /// `DELETE /api/v1/tags/:id`. The server also removes the tag from every
  /// transaction that had it.
  Future<Map<String, dynamic>> deleteTag({
    required String accessToken,
    required String id,
  }) async {
    const fallback = 'Failed to delete tag';
    try {
      final response = await _client
          .delete(
            _uri('/api/v1/tags/${Uri.encodeComponent(id)}'),
            headers: _headers(accessToken),
          )
          .timeout(_timeout);
      if (response.statusCode == 204 || response.statusCode == 200) {
        return {'success': true};
      }
      return _failure(response, fallback);
    } catch (e) {
      _log('deleteTag', e);
      return {'success': false, 'error': fallback};
    }
  }

  Future<Map<String, dynamic>> _getList<T>(
    String operation, {
    required String path,
    required String key,
    required T Function(Map<String, dynamic>) fromJson,
    required bool Function(T) isValid,
    required String accessToken,
    required String fallback,
  }) async {
    try {
      final response = await _client
          .get(_uri(path), headers: _headers(accessToken))
          .timeout(_timeout);
      if (response.statusCode != 200) return _failure(response, fallback);
      final items = <T>[];
      for (final json
          in extractJsonObjectList(jsonDecode(response.body), key: key)) {
        try {
          final item = fromJson(json);
          if (isValid(item)) items.add(item);
        } on FormatException {
          // Skip a malformed record instead of failing the whole list.
        }
      }
      return {'success': true, key: items};
    } catch (e) {
      _log(operation, e);
      return {'success': false, 'error': fallback};
    }
  }

  Map<String, dynamic> _failure(http.Response response, String fallback) {
    if (response.statusCode == 401) {
      return {'success': false, 'error': 'unauthorized'};
    }
    return {
      'success': false,
      'error': extractErrorMessage(response.body, fallback: fallback),
    };
  }

  void _log(String operation, Object error) {
    LogService.instance.error(
      'MetadataManageService',
      '$operation failed with ${error.runtimeType}',
    );
  }
}
