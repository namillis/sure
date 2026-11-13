import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'log_service.dart';
import 'response_list_parser.dart';

/// The household part of [UserProfile] (`family` in the JSON).
class HouseholdProfile {
  const HouseholdProfile({
    required this.name,
    this.currency,
    this.country,
    this.timezone,
    this.dateFormat,
    this.locale,
  });

  final String name;
  final String? currency;
  final String? country;
  final String? timezone;
  final String? dateFormat;
  final String? locale;

  factory HouseholdProfile.fromJson(Map<String, dynamic> json) =>
      HouseholdProfile(
        name: json['name']?.toString() ?? '',
        currency: json['currency']?.toString(),
        country: json['country']?.toString(),
        timezone: json['timezone']?.toString(),
        dateFormat: json['date_format']?.toString(),
        locale: json['locale']?.toString(),
      );
}

/// `GET /api/v1/users/me` on a Sure+ server (`profile.write`).
class UserProfile {
  const UserProfile({
    required this.email,
    this.firstName,
    this.lastName,
    this.locale,
    this.defaultPeriod,
    required this.household,
  });

  final String email;
  final String? firstName;
  final String? lastName;

  /// Null means "automatic" (follow the browser / household).
  final String? locale;
  final String? defaultPeriod;
  final HouseholdProfile household;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final family = json['family'];
    return UserProfile(
      email: json['email']?.toString() ?? '',
      firstName: json['first_name']?.toString(),
      lastName: json['last_name']?.toString(),
      locale: json['locale']?.toString(),
      defaultPeriod: json['default_period']?.toString(),
      household: HouseholdProfile.fromJson(
          family is Map<String, dynamic> ? family : const {}),
    );
  }
}

/// Reads and updates the signed-in user's profile and household preferences
/// (Sure+ `profile.write`). Results are `{'success': bool, ...}` maps, with
/// `'error': 'unauthorized'` on 401 and `'code': 'insufficient_scope'` on a
/// read-only sign-in.
class ProfileService {
  ProfileService({http.Client? client})
      : _client = client ?? http.Client(),
        _ownsClient = client == null;

  final http.Client _client;
  final bool _ownsClient;

  static const _timeout = Duration(seconds: 30);

  void close() {
    if (_ownsClient) _client.close();
  }

  Uri get _uri => Uri.parse('${ApiConfig.baseUrl}/api/v1/users/me');

  Map<String, String> _headers(String accessToken) => {
        ...ApiConfig.getAuthHeaders(accessToken),
        'Content-Type': 'application/json',
      };

  /// `'profile'` holds the [UserProfile].
  Future<Map<String, dynamic>> getProfile({required String accessToken}) =>
      _send('getProfile', 'Failed to load your profile',
          () => _client.get(_uri, headers: _headers(accessToken)));

  /// `PATCH /api/v1/users/me` with [user] as the `user` body (only the
  /// changed fields; household ones under `family_attributes`). `'profile'`
  /// holds the updated [UserProfile].
  Future<Map<String, dynamic>> updateProfile({
    required String accessToken,
    required Map<String, dynamic> user,
  }) =>
      _send(
          'updateProfile',
          'Failed to save your profile',
          () => _client.patch(_uri,
              headers: _headers(accessToken),
              body: jsonEncode({'user': user})));

  Future<Map<String, dynamic>> _send(
    String operation,
    String fallback,
    Future<http.Response> Function() request,
  ) async {
    try {
      final response = await request().timeout(_timeout);
      if (response.statusCode == 200) {
        return {
          'success': true,
          'profile': UserProfile.fromJson(
              jsonDecode(response.body) as Map<String, dynamic>),
        };
      }
      if (response.statusCode == 401) {
        return {'success': false, 'error': 'unauthorized'};
      }
      return {
        'success': false,
        'error': extractErrorMessage(response.body, fallback: fallback),
        if (response.statusCode == 403 &&
            response.body.contains('insufficient_scope'))
          'code': 'insufficient_scope',
      };
    } catch (e) {
      LogService.instance
          .error('ProfileService', '$operation failed with ${e.runtimeType}');
      return {'success': false, 'error': fallback};
    }
  }
}
