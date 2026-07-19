import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(
    auth: FirebaseAuth.instance,
    firestore: FirebaseFirestore.instance,
  );
});

class AuthRepository {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  AuthRepository({
    required FirebaseAuth auth,
    required FirebaseFirestore firestore,
  })  : _auth = auth,
        _firestore = firestore;

  Stream<User?> get authStateChange => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInWithEmail(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(
        email: email, password: password);
  }

  Future<UserCredential> signUpWithEmail(String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
  }

  Future<void> sendEmailVerification() async {
    await _auth.currentUser?.sendEmailVerification();
  }

  Future<void> createUserDocument({
    required String uid,
    required String email,
    required String name,
    required String phone,
    required String gender,
    required DateTime birthDate,
  }) async {
    await _firestore.collection('users').doc(uid).set({
      'email': email,
      'displayName': name,
      'phone': phone,
      'gender': gender,
      'birthDate': Timestamp.fromDate(birthDate),
      'role': 'user',
      'isAdmin': false,
      'wallet_balance': 500000,
      'created_at': Timestamp.now(),
    }, SetOptions(merge: true));
  }

  Future<void> createGoogleUserDocumentIfNeeded(User user) async {
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    if (!userDoc.exists) {
      await _firestore.collection('users').doc(user.uid).set({
        'email': user.email,
        'displayName': user.displayName ?? '',
        'photoURL': user.photoURL ?? '',
        'role': 'user',
        'isAdmin': false,
        'wallet_balance': 500000,
        'created_at': Timestamp.now(),
      });
    }
  }

  Future<Map<String, dynamic>?> getUserData(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }

  // Nạp ví qua backend (Admin SDK) thay vì tự ghi 'wallet_balance' trực tiếp
  // từ client - firestore.rules cấm tuyệt đối user tự sửa field này (chỉ
  // admin mới sửa được), nên ghi thẳng qua Firestore SDK luôn bị
  // permission-denied. Xem app.post('/topup-wallet') ở backend-payos/server.js.
  Future<void> topUpWallet(String uid, int amount) async {
    final idToken = await _auth.currentUser?.getIdToken();
    final response = await http.post(
      Uri.parse('${AppConfig.paymentBackendUrl}/topup-wallet'),
      headers: {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'amount': amount}),
    ).timeout(const Duration(seconds: 15));
    final resData = jsonDecode(response.body);
    if (resData['success'] != true) {
      throw Exception(resData['message'] ?? 'Nạp tiền thất bại');
    }
  }

  // Gửi/xác thực mã OTP đăng nhập (2FA qua email) - xem app.post('/auth/send-otp')
  // và app.post('/auth/verify-otp') ở backend-payos/server.js. Chỉ dùng cho
  // đăng nhập email/password, không áp dụng cho Google Sign-In.
  Future<void> sendLoginOtp() async {
    final idToken = await _auth.currentUser?.getIdToken();
    final response = await http.post(
      Uri.parse('${AppConfig.paymentBackendUrl}/auth/send-otp'),
      headers: {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
    ).timeout(const Duration(seconds: 15));
    final resData = jsonDecode(response.body);
    if (resData['success'] != true) {
      throw Exception(resData['message'] ?? 'Không gửi được mã xác thực');
    }
  }

  Future<void> verifyLoginOtp(String code) async {
    final idToken = await _auth.currentUser?.getIdToken();
    final response = await http.post(
      Uri.parse('${AppConfig.paymentBackendUrl}/auth/verify-otp'),
      headers: {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'code': code}),
    ).timeout(const Duration(seconds: 15));
    final resData = jsonDecode(response.body);
    if (resData['success'] != true) {
      throw Exception(resData['message'] ?? 'Mã xác thực không đúng');
    }
  }

  Future<void> resetPassword(String email) async {
    await _auth.sendPasswordResetEmail(email: email);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    try { await GoogleSignIn().disconnect(); } catch (_) {}
    await GoogleSignIn().signOut();
  }

  Future<UserCredential?> signInWithGoogle() async {
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return await _auth.signInWithCredential(credential);
  }
}
