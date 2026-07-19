import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/room_layout.dart';

/// Streams collection 'room_formats' - nguồn dữ liệu thật cho danh mục định
/// dạng phòng chiếu (Standard/VIP/IMAX/4DX/Gold Class...), thay cho hằng số
/// hardcode kDefaultRoomFormatSpecs (models/room_layout.dart). Admin tự thêm/
/// sửa/archive định dạng qua AdminRoomFormatsScreen, không cần sửa code +
/// build lại app. Mirror đúng pattern theatersProvider
/// (providers/theaters_provider.dart).
///
/// Không lọc status ở query (đọc TOÀN BỘ, kể cả 'archived') - updateRoomFormatCache
/// cần đủ dữ liệu để findRoomFormatSpec() vẫn tra đúng cho phòng cũ đang dùng
/// 1 định dạng đã bị archive; lọc 'active' chỉ áp dụng lúc liệt kê lựa chọn
/// cho phòng MỚI (xem roomFormatsForTheaterSize trong room_layout.dart).
final roomFormatsProvider = StreamProvider<List<RoomFormatSpec>>((ref) {
  return FirebaseFirestore.instance
      .collection('room_formats')
      .snapshots()
      .map((snap) => snap.docs.map((d) => RoomFormatSpec.fromMap(d.id, d.data())).toList());
});
