import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../home/screens/home_screen.dart';
import '../../booking_and_payment/screens/movie_detail_screen.dart';

/// Điều hướng khi người dùng BẤM VÀO 1 push notification (từ trạng thái
/// background hoặc app đã tắt hẳn) - trước đây `onMessageOpenedApp` chỉ log
/// ra console, bấm vào thông báo không mở được gì cả ngoài việc app tự nổi
/// lên màn hình đang có sẵn. Dùng chung cho cả push quảng cáo tự động
/// (backend-payos/server.js sendPromoPushToAllUsers) lẫn broadcast tay của
/// admin/marketing (admin_broadcast_screen.dart) - cả 2 đều gửi field `type`
/// trong `data` payload của FCM message theo đúng quy ước dưới đây.
///
/// Cần `navigatorKey` toàn cục (đặt trên MaterialApp ở main.dart) vì lúc bấm
/// vào thông báo có thể app đang ở bất kỳ màn hình nào, hoặc vừa mới khởi
/// động lại từ trạng thái tắt hẳn (chưa có BuildContext nào sẵn để dùng).
class NotificationRouter {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  static Future<void> handleTap(Map<String, dynamic> data) async {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    final type = data['type'] as String?;
    switch (type) {
      case 'movie':
        final movieId = data['movieId'] as String?;
        if (movieId == null) break;
        try {
          final doc = await FirebaseFirestore.instance.collection('movies').doc(movieId).get();
          if (!doc.exists) break;
          final movieData = {...doc.data()!, 'id': doc.id};
          navigator.push(MaterialPageRoute(builder: (_) => MovieDetailScreen(movieData: movieData)));
          return;
        } catch (_) {
          break; // rơi xuống mở Trang chủ nếu tra phim lỗi (mạng/phim đã bị xoá)
        }
      case 'voucher':
      case 'combo':
      case 'showtime':
      case 'broadcast':
      default:
        break;
    }

    // Mặc định (voucher/combo/showtime/broadcast/không xác định): chưa có
    // màn hình riêng để xem chi tiết voucher/combo ngoài lúc thanh toán, nên
    // mở Trang chủ - nơi banner khuyến mãi/danh sách phim hiển thị sẵn.
    navigator.push(MaterialPageRoute(builder: (_) => const HomeScreen()));
  }
}
