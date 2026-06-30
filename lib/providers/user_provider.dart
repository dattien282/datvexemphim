import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';

// ── Role enum ──────────────────────────────────────────────────────────────────
enum UserRole { user, staff, theaterManager, admin }

extension UserRoleExt on UserRole {
  String get label {
    switch (this) {
      case UserRole.user: return 'Thành viên';
      case UserRole.staff: return 'Nhân viên';
      case UserRole.theaterManager: return 'Quản lý rạp';
      case UserRole.admin: return 'Admin';
    }
  }

  String get firestoreValue {
    switch (this) {
      case UserRole.user: return 'user';
      case UserRole.staff: return 'staff';
      case UserRole.theaterManager: return 'theater_manager';
      case UserRole.admin: return 'admin';
    }
  }

  static UserRole fromString(String? value, {bool legacyIsAdmin = false}) {
    if (legacyIsAdmin && (value == null || value == 'user')) return UserRole.admin;
    switch (value) {
      case 'staff': return UserRole.staff;
      case 'theater_manager': return UserRole.theaterManager;
      case 'admin': return UserRole.admin;
      default: return UserRole.user;
    }
  }
}

// ── UserProfile ────────────────────────────────────────────────────────────────
class UserProfile {
  final String uid;
  final String email;
  final String displayName;
  final String phone;
  final String? avatarUrl;
  final int walletBalance;
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
    required this.isAdmin,
    required this.role,
    this.assignedTheater,
  });

  bool get hasAdminAccess => role == UserRole.admin || isAdmin;
  bool get hasManagerAccess => role == UserRole.theaterManager || hasAdminAccess;
  bool get hasStaffAccess => role == UserRole.staff || hasManagerAccess;

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
      isAdmin: isAdmin,
      role: role ?? this.role,
      assignedTheater: assignedTheater ?? this.assignedTheater,
    );
  }
}

// ── Provider ───────────────────────────────────────────────────────────────────
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map((snap) {
    if (!snap.exists) {
      FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': user.email,
        'wallet_balance': 500000,
        'role': 'user',
        'created_at': Timestamp.now(),
      });
      return UserProfile(
        uid: user.uid,
        email: user.email ?? '',
        displayName: '',
        phone: '',
        walletBalance: 500000,
        isAdmin: false,
        role: UserRole.user,
      );
    }
    return UserProfile.fromMap(user.uid, snap.data()!);
  });
});
