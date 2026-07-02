import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/age_verification_screen.dart';

class AgeVerificationResult {
  final bool canProceed;
  final String? verifiedCccd;

  AgeVerificationResult(this.canProceed, {this.verifiedCccd});
}

class AgeVerificationService {
  Future<AgeVerificationResult> checkAgeRestrictionIfNeeded(
      BuildContext context, Map<String, dynamic> movieData) async {
    final ageRating = (movieData['ageRating'] ?? '').toString().toUpperCase();
    if (ageRating != 'T18') return AgeVerificationResult(true);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return AgeVerificationResult(true);

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final birthTs = doc.data()?['birthDate'] as Timestamp?;

    if (birthTs == null) {
      if (doc.data()?['ageVerified'] == true) return AgeVerificationResult(true);
      if (!context.mounted) return AgeVerificationResult(false);
      final canProceed = await _handleMissingBirthDateGate(context);
      return AgeVerificationResult(canProceed);
    }

    final age = _calculateAge(birthTs.toDate());
    if (age >= 18) return AgeVerificationResult(true);
    
    if (!context.mounted) return AgeVerificationResult(false);
    return await _showAgeRestrictionDialog(context);
  }

  int _calculateAge(DateTime birth) {
    final now = DateTime.now();
    int age = now.year - birth.year;
    if (now.month < birth.month || (now.month == birth.month && now.day < birth.day)) {
      age--;
    }
    return age;
  }

  Future<bool> _handleMissingBirthDateGate(BuildContext context) async {
    final choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF0A0A0A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.badge_rounded, color: Colors.amber, size: 22),
            SizedBox(width: 8),
            Text('CẦN XÁC MINH ĐỘ TUỔI', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        content: const Text(
          'Phim này gắn mác T18. Tài khoản của bạn chưa khai ngày sinh nên hệ thống không xác định được tuổi - vui lòng tải ảnh CCCD (2 mặt) để admin xác minh, hoặc đến quầy mua trực tiếp.',
          style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: const Text('ĐẾN QUẦY MUA TRỰC TIẾP', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
            child: const Text('TẢI CCCD XÁC MINH', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
        ],
      ),
    );

    if (choice == true && context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const AgeVerificationScreen()));
    }
    return false;
  }

  Future<AgeVerificationResult> _showAgeRestrictionDialog(BuildContext context) async {
    final cccdCtrl = TextEditingController();
    bool showCccdInput = false;
    String? error;
    String? verifiedCccd;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: const Color(0xFF0A0A0A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.no_adult_content_rounded, color: Colors.redAccent, size: 22),
                SizedBox(width: 8),
                Text('PHIM GIỚI HẠN 18+', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Phim này gắn mác T18 - chỉ dành cho khán giả từ 18 tuổi trở lên. Theo thông tin đăng ký, bạn chưa đủ 18 tuổi.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
                if (!showCccdInput) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Nếu bạn đã khai sai ngày sinh lúc đăng ký và thực tế đã đủ 18 tuổi, có thể nhập số CCCD để xác minh và tiếp tục đặt vé.',
                    style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: cccdCtrl,
                    keyboardType: TextInputType.number,
                    maxLength: 12,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: 'Nhập số CCCD (12 số)',
                      hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                      errorText: error,
                      filled: true,
                      fillColor: const Color(0xFF1E1E2A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx, false),
                child: const Text('ĐẾN QUẦY MUA TRỰC TIẾP', style: TextStyle(color: Colors.grey, fontSize: 11)),
              ),
              if (!showCccdInput)
                ElevatedButton(
                  onPressed: () => setDialogState(() => showCccdInput = true),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                  child: const Text('NHẬP CCCD XÁC MINH', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 12)),
                )
              else
                ElevatedButton(
                  onPressed: () {
                    final val = cccdCtrl.text.trim();
                    if (!RegExp(r'^\d{12}$').hasMatch(val)) {
                      setDialogState(() => error = 'Số CCCD phải gồm đúng 12 chữ số');
                      return;
                    }
                    verifiedCccd = val;
                    Navigator.pop(dialogCtx, true);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
                  child: const Text('XÁC NHẬN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
        ),
      ),
    );

    return AgeVerificationResult(result == true, verifiedCccd: verifiedCccd);
  }
}
