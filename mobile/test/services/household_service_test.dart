import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sure_mobile/models/household.dart';
import 'package:sure_mobile/services/api_config.dart';
import 'package:sure_mobile/services/household_service.dart';

void main() {
  late String previousBaseUrl;
  final requests = <http.Request>[];

  setUp(() {
    previousBaseUrl = ApiConfig.baseUrl;
    ApiConfig.setBaseUrl('https://sure.example.com');
    requests.clear();
  });
  tearDown(() => ApiConfig.setBaseUrl(previousBaseUrl));

  HouseholdService service(int status, Object? body) =>
      HouseholdService(client: MockClient((request) async {
        requests.add(request);
        return http.Response(body == null ? '' : jsonEncode(body), status);
      }));

  test('members parses members, invitations and delivery', () async {
    final result = await service(200, {
      'members': [
        {
          'id': 'u1',
          'name': 'Ada',
          'email': 'ada@example.com',
          'role': 'admin',
          'avatar_url': null,
          'is_current_user': true,
        },
      ],
      'pending_invitations': [
        {
          'id': 'i1',
          'email': 'bob@example.com',
          'role': 'guest',
          'created_at': '2026-11-01T10:00:00Z',
          'expires_at': '2026-11-08T10:00:00Z',
        },
      ],
      'can_manage_invitations': true,
      'invitations_enabled': true,
      'invitation_delivery': 'link_only',
    }).members(accessToken: 't');

    expect(requests.single.url.path, '/api/v1/family/members');
    final household = result['household'] as Household;
    expect(household.members.single.isCurrentUser, isTrue);
    expect(household.invitations.single.role, 'guest');
    expect(household.invitations.single.expiresAt, isNotNull);
    expect(household.canManageInvitations, isTrue);
    expect(household.linkOnly, isTrue);
  });

  test('invite posts email and role and returns the delivery', () async {
    final result = await service(201, {'id': 'i2', 'delivery': 'email'})
        .invite(accessToken: 't', email: 'c@example.com', role: 'member');
    expect(requests.single.method, 'POST');
    expect(requests.single.url.path, '/api/v1/invitations');
    expect(jsonDecode(requests.single.body), {
      'invitation': {'email': 'c@example.com', 'role': 'member'},
    });
    expect(result['delivery'], 'email');
  });

  test('a 422 carries the server message, code and status', () async {
    final result = await service(422, {
      'error': 'validation_failed',
      'message': 'This person is already a member of your household.',
    }).invite(accessToken: 't', email: 'a@example.com', role: 'member');
    expect(result['success'], isFalse);
    expect(result['status'], 422);
    expect(result['code'], 'validation_failed');
    expect(result['error'], 'This person is already a member of your household.');
  });

  test('a 401 reports unauthorized', () async {
    final result = await service(401, {'error': 'unauthorized'})
        .budgetSharing(accessToken: 't');
    expect(result['error'], 'unauthorized');
  });

  test('revoke deletes the invitation and accepts 204', () async {
    final result =
        await service(204, null).revokeInvitation(accessToken: 't', id: 'i1');
    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/api/v1/invitations/i1');
    expect(result['success'], isTrue);
  });

  test('account sharing PATCHes one member, or include_in_finances', () async {
    final sharing = {
      'account_id': 'a1',
      'is_owner': true,
      'owner': {'id': 'u1', 'name': 'Ada'},
      'permission': null,
      'include_in_finances': null,
      'permissions': ['full_control', 'read_write', 'read_only'],
      'members': [
        {'user_id': 'u2', 'name': 'Bob', 'permission': 'read_only'},
      ],
    };
    final s = service(200, sharing);
    final result = await s.setAccountMember(
        accessToken: 't', accountId: 'a1', userId: 'u2', permission: 'none');
    expect(requests.last.method, 'PATCH');
    expect(requests.last.url.path, '/api/v1/accounts/a1/sharing');
    expect(jsonDecode(requests.last.body), {
      'sharing': {
        'members': [
          {'user_id': 'u2', 'permission': 'none'},
        ],
      },
    });
    final parsed = result['sharing'] as AccountSharing;
    expect(parsed.isOwner, isTrue);
    expect(parsed.ownerName, 'Ada');
    expect(parsed.members.single.permission, 'read_only');

    await s.setIncludeInFinances(
        accessToken: 't', accountId: 'a1', include: false);
    expect(jsonDecode(requests.last.body), {
      'sharing': {'include_in_finances': false},
    });
  });

  test('budget sharing PATCHes budget_shares members', () async {
    final result = await service(200, {
      'personal_budgets': true,
      'permissions': ['read_write', 'read_only'],
      'members': [
        {'user_id': 'u2', 'name': 'Bob', 'permission': 'read_write'},
      ],
    }).setBudgetMember(accessToken: 't', userId: 'u2', permission: 'read_write');
    expect(requests.single.url.path, '/api/v1/budget_shares');
    expect(jsonDecode(requests.single.body), {
      'budget_shares': {
        'members': [
          {'user_id': 'u2', 'permission': 'read_write'},
        ],
      },
    });
    expect((result['sharing'] as BudgetSharing).personalBudgets, isTrue);
  });
}
