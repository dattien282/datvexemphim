import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../providers/user_provider.dart';

class MembershipScreen extends ConsumerStatefulWidget {
  const MembershipScreen({super.key});

  @override
  ConsumerState<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends ConsumerState<MembershipScreen> {
  Map<String, dynamic> _getTierInfo(int points) {
    if (points >= 10000) {
      return {
        'name': 'KIM CƯƠNG',
        'color': const Color(0xFFB9F2FF), // Diamond cyan
        'gradient': [const Color(0xFF00B4DB), const Color(0xFF0083B0)],
        'nextTier': null,
        'pointsNeeded': 0,
        'progress': 1.0,
        'benefits': [
          'Giảm 15% tổng hoá đơn cho mỗi lần thanh toán.',
          'Miễn phí 1 combo bắp nước tiêu chuẩn mỗi tháng.',
          'Ưu tiên chọn ghế VIP không phụ thu.',
          'Lối đi riêng tại quầy vé (Fast-track).'
        ],
      };
    } else if (points >= 5000) {
      return {
        'name': 'VÀNG',
        'color': Colors.amberAccent,
        'gradient': [const Color(0xFFFFD700), const Color(0xFFDAA520)],
        'nextTier': 'KIM CƯƠNG',
        'pointsNeeded': 10000 - points,
        'progress': (points - 5000) / 5000,
        'benefits': [
          'Giảm 10% tổng hoá đơn cho mỗi lần thanh toán.',
          'Tặng 1 bắp nước lớn vào tháng sinh nhật.',
          'Đổi vé xem phim miễn phí (Cần 50.000 điểm).'
        ],
      };
    } else if (points >= 1000) {
      return {
        'name': 'BẠC',
        'color': Colors.grey.shade400,
        'gradient': [const Color(0xFFBDBDBD), const Color(0xFF757575)],
        'nextTier': 'VÀNG',
        'pointsNeeded': 5000 - points,
        'progress': (points - 1000) / 4000,
        'benefits': [
          'Giảm 5% tổng hoá đơn cho mỗi lần thanh toán.',
          'Tặng voucher 50K vào tháng sinh nhật.'
        ],
      };
    } else {
      return {
        'name': 'ĐỒNG',
        'color': Colors.brown.shade300,
        'gradient': [const Color(0xFFA1887F), const Color(0xFF5D4037)],
        'nextTier': 'BẠC',
        'pointsNeeded': 1000 - points,
        'progress': points / 1000,
        'benefits': [
          'Tích điểm cho mỗi lần giao dịch (1.000đ = 1 điểm).',
          'Sử dụng điểm tích luỹ để trừ trực tiếp vào hoá đơn.',
        ],
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = ref.watch(userProfileProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        centerTitle: true,
        title: const Text('THẺ THÀNH VIÊN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 0.5)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: userState.when(
        data: (profile) {
          if (profile == null) {
            return const Center(child: Text('Không tìm thấy thông tin thành viên.', style: TextStyle(color: Colors.white70)));
          }

          final int points = profile.loyaltyPoints;
          final tierInfo = _getTierInfo(points);

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Virtual Membership Card
                _buildVirtualCard(profile.displayName, profile.uid, points, tierInfo),

                const SizedBox(height: 32),

                // 2. Progress to next tier
                if (tierInfo['nextTier'] != null) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Hạng hiện tại: ${tierInfo['name']}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      Text('${tierInfo['pointsNeeded']} điểm nữa để lên ${tierInfo['nextTier']}', style: TextStyle(color: tierInfo['color'], fontSize: 13, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: tierInfo['progress'],
                      minHeight: 10,
                      backgroundColor: const Color(0xFF1E1E2A),
                      valueColor: AlwaysStoppedAnimation<Color>(tierInfo['color']),
                    ),
                  ),
                ] else ...[
                  Center(
                    child: Text('Chúc mừng! Bạn đã đạt hạng cao nhất.', style: TextStyle(color: tierInfo['color'], fontSize: 14, fontWeight: FontWeight.bold)),
                  ),
                ],

                const SizedBox(height: 40),

                // 3. Benefits
                const Text('QUYỀN LỢI HẠNG', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161F),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF2A2A35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: (tierInfo['benefits'] as List<String>).map((benefit) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.check_circle_rounded, color: tierInfo['color'], size: 20),
                            const SizedBox(width: 12),
                            Expanded(child: Text(benefit, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4))),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator(color: Colors.amber)),
        error: (err, stack) => Center(child: Text('Lỗi: $err', style: const TextStyle(color: Colors.red))),
      ),
    );
  }

  Widget _buildVirtualCard(String name, String userId, int points, Map<String, dynamic> tierInfo) {
    return Container(
      // Trước đây ép cứng height: 220 + dùng Spacer() để đẩy nội dung giãn
      // đều - nhưng tổng chiều cao thật của header + QR + tên/điểm luôn nhỉnh
      // hơn 220 một chút (tuỳ font hệ thống/độ phóng chữ), gây tràn
      // "RenderFlex overflowed". Bỏ height cố định, để Column tự co theo nội
      // dung thật, thay Spacer bằng khoảng cách cố định.
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: tierInfo['gradient'],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: tierInfo['color'].withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('STELLA MEMBER', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1.5)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(tierInfo['name'], style: TextStyle(color: tierInfo['color'], fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Barcode for scanning
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: QrImageView(
              data: userId,
              size: 80,
              version: QrVersions.auto,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('TÊN THÀNH VIÊN', style: TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(name.toUpperCase(), style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w900), overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('ĐIỂM TÍCH LŨY', style: TextStyle(color: Colors.black54, fontSize: 10, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text('$points pts', style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w900)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
