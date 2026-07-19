import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_provider.dart';
import '../models/user_profile.dart';

export '../models/user_profile.dart';

final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .snapshots()
      .map((snap) {
    if (!snap.exists) {
      return UserProfile(
        uid: user.uid,
        email: user.email ?? '',
        displayName: '',
        phone: '',
        walletBalance: 500000,
        loyaltyPoints: 0,
        isAdmin: false,
        role: UserRole.user,
      );
    }
    return UserProfile.fromMap(user.uid, snap.data()!);
  });
});
