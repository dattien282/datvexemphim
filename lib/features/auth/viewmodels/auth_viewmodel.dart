import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../repositories/auth_repository.dart';

// Provide current user's data map from Firestore
final userModelProvider = StateProvider<Map<String, dynamic>?>((ref) => null);

// Provide AuthViewModel
final authViewModelProvider = StateNotifierProvider<AuthViewModel, AsyncValue<User?>>((ref) {
  return AuthViewModel(ref: ref, repository: ref.watch(authRepositoryProvider));
});

class AuthViewModel extends StateNotifier<AsyncValue<User?>> {
  final Ref _ref;
  final AuthRepository _repository;

  AuthViewModel({required Ref ref, required AuthRepository repository})
      : _ref = ref,
        _repository = repository,
        super(const AsyncValue.loading()) {
    _init();
  }

  void _init() {
    _repository.authStateChange.listen((user) async {
      state = AsyncValue.data(user);
      if (user != null) {
        await _fetchUserData(user.uid);
      } else {
        _ref.read(userModelProvider.notifier).state = null;
      }
    });
  }

  Future<void> _fetchUserData(String uid) async {
    try {
      final data = await _repository.getUserData(uid);
      _ref.read(userModelProvider.notifier).state = data;
    } catch (e) {
      print('Error fetching user data: $e');
    }
  }

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    try {
      state = const AsyncValue.loading();
      await _repository.signInWithEmail(email, password);
      return {'success': true};
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.data(_repository.currentUser); // restore state
      String message = 'Đăng nhập thất bại! (mã lỗi: ${e.code})';
      if (e.code == 'user-not-found' || e.code == 'wrong-password' || e.code == 'invalid-credential') {
        message = 'Email hoặc mật khẩu không chính xác!';
      } else if (e.code == 'network-request-failed') {
        message = 'Không kết nối được tới máy chủ Firebase - kiểm tra lại mạng Internet của thiết bị.';
      } else if (e.code == 'operation-not-allowed') {
        message = 'Đăng nhập Email/Password chưa được bật trong Firebase Console.';
      } else if (e.code == 'user-disabled') {
        message = 'Tài khoản này đã bị vô hiệu hoá.';
      } else if (e.code == 'too-many-requests') {
        message = 'Thử sai quá nhiều lần, vui lòng thử lại sau ít phút.';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      state = AsyncValue.data(_repository.currentUser);
      return {'success': false, 'message': 'Đã xảy ra lỗi: $e'};
    }
  }

  Future<Map<String, dynamic>> signUp({
    required String email,
    required String password,
    required String name,
    required String phone,
    required String gender,
    required DateTime birthDate,
  }) async {
    try {
      state = const AsyncValue.loading();
      final cred = await _repository.signUpWithEmail(email, password);
      if (cred.user != null) {
        await _repository.createUserDocument(
          uid: cred.user!.uid,
          email: email,
          name: name,
          phone: phone,
          gender: gender,
          birthDate: birthDate,
        );
        try {
          await _repository.sendEmailVerification();
        } catch (_) {}
      }
      return {'success': true};
    } on FirebaseAuthException catch (e) {
      state = AsyncValue.data(_repository.currentUser);
      String message = 'Đăng ký thất bại! (mã lỗi: ${e.code})';
      if (e.code == 'email-already-in-use') {
        message = 'Email này đã được sử dụng!';
      } else if (e.code == 'weak-password') {
        message = 'Mật khẩu quá yếu!';
      } else if (e.code == 'network-request-failed') {
        message = 'Không kết nối được tới máy chủ Firebase - kiểm tra lại mạng Internet của thiết bị.';
      } else if (e.code == 'operation-not-allowed') {
        message = 'Đăng ký Email/Password chưa được bật trong Firebase Console.';
      } else if (e.code == 'invalid-email') {
        message = 'Email không đúng định dạng!';
      }
      return {'success': false, 'message': message};
    } catch (e) {
      state = AsyncValue.data(_repository.currentUser);
      return {'success': false, 'message': 'Đã xảy ra lỗi: $e'};
    }
  }

  Future<Map<String, dynamic>> signInWithGoogle() async {
    try {
      state = const AsyncValue.loading();
      final cred = await _repository.signInWithGoogle();
      if (cred != null && cred.user != null) {
        await _repository.createGoogleUserDocumentIfNeeded(cred.user!);
        return {'success': true};
      }
      state = AsyncValue.data(_repository.currentUser);
      return {'success': false, 'message': 'Đăng nhập Google bị hủy'};
    } catch (e) {
      state = AsyncValue.data(_repository.currentUser);
      return {'success': false, 'message': 'Lỗi đăng nhập Google: $e'};
    }
  }

  Future<Map<String, dynamic>> topUpWallet(int amount) async {
    try {
      final user = _repository.currentUser;
      if (user == null) return {'success': false, 'message': 'Chưa đăng nhập'};
      
      await _repository.topUpWallet(user.uid, amount);
      await _fetchUserData(user.uid); // Refresh data
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': 'Nạp tiền thất bại: $e'};
    }
  }

  Future<void> resetPassword(String email) async {
    await _repository.resetPassword(email);
  }

  Future<Map<String, dynamic>> sendLoginOtp() async {
    try {
      await _repository.sendLoginOtp();
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  Future<Map<String, dynamic>> verifyLoginOtp(String code) async {
    try {
      await _repository.verifyLoginOtp(code);
      return {'success': true};
    } catch (e) {
      return {'success': false, 'message': e.toString().replaceFirst('Exception: ', '')};
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();
  }
}
