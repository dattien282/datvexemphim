import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../../core/constants.dart';

/// Tài khoản không có birthDate (vd. đăng nhập Google chưa từng khai ngày
/// sinh) muốn đặt vé phim T18 phải tải CCCD 2 mặt lên để admin duyệt thủ
/// công - thay vì cho qua không kiểm tra gì như trước, hoặc chỉ tự nhập số
/// CCCD tay (không xác minh được, dễ khai gian).
class AgeVerificationScreen extends StatefulWidget {
  const AgeVerificationScreen({super.key});

  @override
  State<AgeVerificationScreen> createState() => _AgeVerificationScreenState();
}

class _AgeVerificationScreenState extends State<AgeVerificationScreen> {
  File? _frontImage;
  File? _backImage;
  bool _submitting = false;

  Future<void> _pickImage(bool isFront) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null) return;
    setState(() {
      if (isFront) {
        _frontImage = File(picked.path);
      } else {
        _backImage = File(picked.path);
      }
    });
  }

  // Ảnh CCCD là dữ liệu nhạy cảm - trước đây dùng "unsigned upload preset" của
  // Cloudinary, cho phép BẤT KỲ AI (không cần đăng nhập) upload thẳng lên vì
  // cloud name + preset bị hardcode sẵn trong app (trích xuất được bằng cách
  // decompile). Giờ phải xin chữ ký từ backend (yêu cầu Firebase ID token hợp
  // lệ) qua /cloudinary-sign trước - Cloudinary chỉ chấp nhận đúng chữ ký đó,
  // và public_id chứa UUID ngẫu nhiên nên URL ảnh khó dò ra dù vẫn public.
  Future<String?> _uploadToCloudinary(File file, String kind) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    final idToken = await user.getIdToken();

    final signRes = await http.post(
      Uri.parse('${AppConfig.paymentBackendUrl}/cloudinary-sign'),
      headers: {
        'Content-Type': 'application/json',
        if (idToken != null) 'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({'kind': kind}),
    ).timeout(const Duration(seconds: 10));
    final signData = jsonDecode(signRes.body);
    if (signData['success'] != true) return null;

    final url = Uri.parse('https://api.cloudinary.com/v1_1/${signData['cloudName']}/image/upload');
    final request = http.MultipartRequest('POST', url)
      ..fields['api_key'] = signData['apiKey']
      ..fields['timestamp'] = signData['timestamp'].toString()
      ..fields['public_id'] = signData['publicId']
      ..fields['signature'] = signData['signature']
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final response = await request.send();
    if (response.statusCode == 200) {
      final responseData = await response.stream.bytesToString();
      final jsonMap = jsonDecode(responseData);
      return jsonMap['secure_url'];
    }
    return null;
  }

  Future<void> _submit() async {
    if (_frontImage == null || _backImage == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final requestId = FirebaseFirestore.instance.collection('age_verification_requests').doc().id;

      final frontUrl = await _uploadToCloudinary(_frontImage!, 'front');
      final backUrl = await _uploadToCloudinary(_backImage!, 'back');

      if (frontUrl == null || backUrl == null) {
        throw Exception('Upload ảnh thất bại. Vui lòng thử lại.');
      }

      await FirebaseFirestore.instance.collection('age_verification_requests').doc(requestId).set({
        'userId': user.uid,
        'email': user.email,
        'frontUrl': frontUrl,
        'backUrl': backUrl,
        'status': 'pending',
        'createdAt': Timestamp.now(),
      });

      // Gửi thông báo cho user
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': user.uid,
        'title': 'Yêu cầu Xác minh độ tuổi',
        'body': 'Ảnh CCCD của bạn đã được tải lên thành công. Vui lòng chờ Admin phê duyệt để có thể đặt vé phim T18+.',
        'type': 'verification_pending',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã gửi yêu cầu xác minh! Vui lòng quay lại đặt vé sau khi được duyệt.'), backgroundColor: Colors.teal),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi gửi yêu cầu: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('XÁC MINH ĐỘ TUỔI', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: user == null
          ? const Center(child: Text('Vui lòng đăng nhập lại.', style: TextStyle(color: Colors.white38)))
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('age_verification_requests')
                  .where('userId', isEqualTo: user.uid)
                  .orderBy('createdAt', descending: true)
                  .limit(1)
                  .snapshots(),
              builder: (context, snap) {
                final latest = (snap.data?.docs ?? []).isEmpty ? null : snap.data!.docs.first;
                final status = latest != null ? (latest.data() as Map)['status'] as String? : null;

                if (status == 'pending') {
                  return const _StatusView(
                    icon: Icons.hourglass_top_rounded,
                    color: Colors.orangeAccent,
                    title: 'ĐANG CHỜ DUYỆT',
                    message: 'Yêu cầu xác minh CCCD của bạn đang chờ admin kiểm tra. Vui lòng quay lại đặt vé sau khi được duyệt (thường trong vòng vài giờ).',
                  );
                }
                if (status == 'approved') {
                  return const _StatusView(
                    icon: Icons.verified_rounded,
                    color: Colors.greenAccent,
                    title: 'ĐÃ XÁC MINH',
                    message: 'Tài khoản của bạn đã được xác minh đủ 18 tuổi. Bạn có thể tiếp tục đặt vé phim T18.',
                  );
                }

                return _buildUploadForm(status == 'rejected');
              },
            ),
    );
  }

  Widget _buildUploadForm(bool wasRejected) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wasRejected)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
              child: const Text('Yêu cầu trước đã bị từ chối (ảnh không rõ/không hợp lệ). Vui lòng tải ảnh khác và gửi lại.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12)),
            ),
          const Text(
            'Phim bạn muốn xem có mác 18+. Vì tài khoản chưa khai ngày sinh, vui lòng tải ảnh CCCD (2 mặt) để admin xác minh bạn đủ 18 tuổi trước khi tiếp tục đặt vé.',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 20),
          _buildImagePicker('Mặt trước CCCD', _frontImage, () => _pickImage(true)),
          const SizedBox(height: 16),
          _buildImagePicker('Mặt sau CCCD', _backImage, () => _pickImage(false)),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: (_frontImage != null && _backImage != null && !_submitting) ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber,
                disabledBackgroundColor: Colors.white10,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Text('GỬI YÊU CẦU XÁC MINH', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePicker(String label, File? image, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onTap,
          child: Container(
            height: 160,
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF16161F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
              image: image != null ? DecorationImage(image: FileImage(image), fit: BoxFit.cover) : null,
            ),
            child: image == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.upload_file_rounded, color: Colors.white38, size: 32),
                        SizedBox(height: 8),
                        Text('Chạm để tải ảnh lên', style: TextStyle(color: Colors.white38, fontSize: 12)),
                      ],
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }
}

class _StatusView extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  const _StatusView({required this.icon, required this.color, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 56),
            const SizedBox(height: 16),
            Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
