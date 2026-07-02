import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Records an admin mutation (movie/voucher CRUD, role changes) for
/// after-the-fact review. Written client-side because admin already has
/// elevated trust under firestore.rules; reads/writes on this collection are
/// restricted to admins only (see firestore.rules).
Future<void> logAdminAction({
  required String action,
  required String targetCollection,
  required String targetId,
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
}) async {
  final admin = FirebaseAuth.instance.currentUser;
  try {
    await FirebaseFirestore.instance.collection('admin_audit_log').add({
      'adminUid': admin?.uid,
      'adminEmail': admin?.email,
      'action': action,
      'targetCollection': targetCollection,
      'targetId': targetId,
      'before': before,
      'after': after,
      'timestamp': Timestamp.now(),
    });
  } catch (_) {
    // Best-effort: không chặn thao tác chính nếu ghi log thất bại.
  }
}
