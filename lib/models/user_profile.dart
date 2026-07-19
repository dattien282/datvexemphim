
enum UserRole { user, staff, theaterManager, admin, accountant, marketing }

extension UserRoleExt on UserRole {
  String get label {
    switch (this) {
      case UserRole.user: return 'Thành viên';
      case UserRole.staff: return 'Nhân viên';
      case UserRole.theaterManager: return 'Quản lý rạp';
      case UserRole.admin: return 'Admin';
      case UserRole.accountant: return 'Kế toán';
      case UserRole.marketing: return 'Marketing';
    }
  }

  String get firestoreValue {
    switch (this) {
      case UserRole.user: return 'user';
      case UserRole.staff: return 'staff';
      case UserRole.theaterManager: return 'theater_manager';
      case UserRole.admin: return 'admin';
      case UserRole.accountant: return 'accountant';
      case UserRole.marketing: return 'marketing';
    }
  }

  static UserRole fromString(String? value, {bool legacyIsAdmin = false}) {
    if (legacyIsAdmin && (value == null || value == 'user')) return UserRole.admin;
    switch (value) {
      case 'staff': return UserRole.staff;
      case 'theater_manager': return UserRole.theaterManager;
      case 'admin': return UserRole.admin;
      case 'accountant': return UserRole.accountant;
      case 'marketing': return UserRole.marketing;
      default: return UserRole.user;
    }
  }
}

class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String phone;
  final String? avatarUrl;
  final int walletBalance;
  final int loyaltyPoints;
  final bool isAdmin;           // backward compat
  final UserRole role;
  final String? assignedTheater; // dành cho staff & theater_manager

  const UserProfile({
    required this.uid,
    required this.email,
    required this.displayName,
    required this.phone,
    this.avatarUrl,
    required this.walletBalance,
    this.loyaltyPoints = 0,
    required this.isAdmin,
    required this.role,
    this.assignedTheater,
  });

  bool get hasAdminAccess => role == UserRole.admin || isAdmin;
  bool get hasManagerAccess => role == UserRole.theaterManager || hasAdminAccess;
  bool get hasStaffAccess => role == UserRole.staff || hasManagerAccess;

  // Accountant/marketing dùng chung AdminDashboardScreen (màn đó tự lọc menu
  // theo role) nhưng KHÔNG nằm trong chuỗi phân cấp staff/manager/admin -
  // getter riêng để _navigateByRole đưa họ vào đúng dashboard.
  bool get hasBackofficeAccess =>
      role == UserRole.accountant || role == UserRole.marketing || hasAdminAccess;

  factory UserProfile.fromMap(String uid, Map<String, dynamic> data) {
    final legacyAdmin = data['isAdmin'] == true;
    final role = UserRoleExt.fromString(data['role'] as String?, legacyIsAdmin: legacyAdmin);
    return UserProfile(
      uid: uid,
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      phone: data['phone'] ?? '',
      avatarUrl: data['avatarUrl'],
      walletBalance: (data['wallet_balance'] as num? ?? 500000).toInt(),
      loyaltyPoints: (data['loyalty_points'] as num? ?? 0).toInt(),
      isAdmin: legacyAdmin || role == UserRole.admin,
      role: role,
      assignedTheater: data['assignedTheater'],
    );
  }

  UserProfile copyWith({
    String? displayName,
    String? phone,
    String? avatarUrl,
    int? walletBalance,
    int? loyaltyPoints,
    UserRole? role,
    String? assignedTheater,
  }) {
    return UserProfile(
      uid: uid,
      email: email,
      displayName: displayName ?? this.displayName,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      walletBalance: walletBalance ?? this.walletBalance,
      loyaltyPoints: loyaltyPoints ?? this.loyaltyPoints,
      isAdmin: isAdmin,
      role: role ?? this.role,
      assignedTheater: assignedTheater ?? this.assignedTheater,
    );
  }
}
