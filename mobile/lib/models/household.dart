/// Household members, invitations and sharing on Sure+ servers
/// (`household.members`, `accounts.sharing`, `budgets.sharing`).
library;

/// One person in the household, from `GET /api/v1/family/members`.
class HouseholdMember {
  const HouseholdMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.isCurrentUser = false,
  });

  final String id;
  final String name;
  final String email;

  /// `guest`, `member`, `admin` or `super_admin`.
  final String role;
  final bool isCurrentUser;

  factory HouseholdMember.fromJson(Map<String, dynamic> json) =>
      HouseholdMember(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? '',
        isCurrentUser: json['is_current_user'] == true,
      );
}

/// A pending invitation (the token is never in the API).
class HouseholdInvitation {
  const HouseholdInvitation({
    required this.id,
    required this.email,
    required this.role,
    this.expiresAt,
  });

  final String id;
  final String email;
  final String role;
  final DateTime? expiresAt;

  factory HouseholdInvitation.fromJson(Map<String, dynamic> json) =>
      HouseholdInvitation(
        id: json['id']?.toString() ?? '',
        email: json['email']?.toString() ?? '',
        role: json['role']?.toString() ?? '',
        expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? '')
            ?.toLocal(),
      );
}

/// `GET /api/v1/family/members`.
class Household {
  const Household({
    required this.members,
    required this.invitations,
    this.canManageInvitations = false,
    this.invitationsEnabled = true,
    this.invitationDelivery,
  });

  final List<HouseholdMember> members;
  final List<HouseholdInvitation> invitations;
  final bool canManageInvitations;
  final bool invitationsEnabled;

  /// `email` or `link_only` (self-hosted servers send no invitation email).
  final String? invitationDelivery;

  bool get linkOnly => invitationDelivery == 'link_only';

  factory Household.fromJson(Map<String, dynamic> json) => Household(
        members: _objects(json['members'])
            .map(HouseholdMember.fromJson)
            .toList(),
        invitations: _objects(json['pending_invitations'])
            .map(HouseholdInvitation.fromJson)
            .toList(),
        canManageInvitations: json['can_manage_invitations'] == true,
        invitationsEnabled: json['invitations_enabled'] != false,
        invitationDelivery: json['invitation_delivery']?.toString(),
      );
}

/// One family member's share of an account or of the caller's budget.
/// [permission] is `none` when nothing is shared.
class ShareMember {
  const ShareMember({
    required this.userId,
    required this.name,
    required this.permission,
  });

  final String userId;
  final String name;
  final String permission;

  ShareMember withPermission(String value) =>
      ShareMember(userId: userId, name: name, permission: value);

  factory ShareMember.fromJson(Map<String, dynamic> json) => ShareMember(
        userId: json['user_id']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        permission: json['permission']?.toString() ?? 'none',
      );
}

/// `GET /api/v1/accounts/:id/sharing`. The owner gets [members]; someone the
/// account is shared with gets [permission] and [includeInFinances].
class AccountSharing {
  const AccountSharing({
    required this.isOwner,
    this.ownerName,
    this.permission,
    this.includeInFinances,
    this.members = const [],
  });

  final bool isOwner;
  final String? ownerName;
  final String? permission;
  final bool? includeInFinances;
  final List<ShareMember> members;

  factory AccountSharing.fromJson(Map<String, dynamic> json) {
    final owner = json['owner'];
    return AccountSharing(
      isOwner: json['is_owner'] == true,
      ownerName: owner is Map ? owner['name']?.toString() : null,
      permission: json['permission']?.toString(),
      includeInFinances: json['include_in_finances'] is bool
          ? json['include_in_finances'] as bool
          : null,
      members: _objects(json['members']).map(ShareMember.fromJson).toList(),
    );
  }
}

/// `GET /api/v1/budget_shares`: who sees the caller's personal budget.
class BudgetSharing {
  const BudgetSharing({required this.personalBudgets, this.members = const []});

  /// False when the family has no personal budgets; the screen is hidden.
  final bool personalBudgets;
  final List<ShareMember> members;

  factory BudgetSharing.fromJson(Map<String, dynamic> json) => BudgetSharing(
        personalBudgets: json['personal_budgets'] == true,
        members: _objects(json['members']).map(ShareMember.fromJson).toList(),
      );
}

List<Map<String, dynamic>> _objects(Object? value) => value is List
    ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
    : const [];
