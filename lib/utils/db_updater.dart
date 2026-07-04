import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/showtime.dart';
import '../models/room_layout.dart';

class TheaterConfig {
  final int roomCount;
  final List<String> roomLayouts; // Format của từng phòng từ Rạp 1 đến Rạp N
  final double lat;
  final double lng;
  final String address;
  const TheaterConfig(this.roomCount, this.roomLayouts, this.lat, this.lng, this.address);
}

final Map<String, TheaterConfig> kTheaterConfigs = {
  'Tân Phú': const TheaterConfig(8, ['Dolby Atmos', 'Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 10.8015, 106.6166, '30 Bờ Bao Tân Thắng, Sơn Kỳ, Tân Phú, Thành phố Hồ Chí Minh'),
  'Crescent': const TheaterConfig(7, ['VIP', 'Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard'], 10.7296, 106.7208, '101 Tôn Dật Tiên, Tân Phú, Quận 7, Thành phố Hồ Chí Minh'),
  'Gigamall': const TheaterConfig(10, ['IMAX', 'Dolby Atmos', 'Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard', 'Standard', 'Standard'], 10.8276, 106.7214, '240-242 Phạm Văn Đồng, Hiệp Bình Chánh, Thủ Đức, Thành phố Hồ Chí Minh'),
  'Landmark': const TheaterConfig(9, ['IMAX', 'VIP', 'Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 10.7950, 106.7218, 'Vinhomes Central Park, 720A Điện Biên Phủ, Phường 22, Bình Thạnh, Thành phố Hồ Chí Minh'),
  'Vạn Hạnh': const TheaterConfig(8, ['4DX', 'Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 10.7758, 106.6690, '11 Sư Vạn Hạnh, Phường 12, Quận 10, Thành phố Hồ Chí Minh'),
  'Estella': const TheaterConfig(6, ['VIP', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard'], 10.8016, 106.7397, '88 Song Hành, An Phú, Thủ Đức, Thành phố Hồ Chí Minh'),
  'Nguyễn Du': const TheaterConfig(5, ['Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 10.7744, 106.6953, '116 Nguyễn Du, Bến Thành, Quận 1, Thành phố Hồ Chí Minh'),
  'Mipec': const TheaterConfig(7, ['IMAX', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 21.0425, 105.8679, '2 Long Biên 2, Ngọc Lâm, Long Biên, Hà Nội'),
  'Royal': const TheaterConfig(11, ['IMAX', '4DX', 'Dolby Atmos', 'VIP', 'Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 21.0028, 105.8152, '72A Nguyễn Trãi, Thượng Đình, Thanh Xuân, Hà Nội'),
  'Times': const TheaterConfig(10, ['IMAX', 'ScreenX', 'Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard', 'Standard', 'Standard'], 20.9959, 105.8669, '458 Minh Khai, Vĩnh Phú, Hai Bà Trưng, Hà Nội'),
  'Cần Thơ': const TheaterConfig(6, ['Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard'], 10.0345, 105.7865, '1 Đại lộ Hòa Bình, Tân An, Ninh Kiều, Cần Thơ'),
  'Đà Nẵng': const TheaterConfig(7, ['IMAX', 'Dolby Atmos', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard'], 16.0718, 108.2307, '910A Ngô Quyền, An Hải Bắc, Sơn Trà, Đà Nẵng'),
};

TheaterConfig _getConfigForTheater(String name) {
  for (final key in kTheaterConfigs.keys) {
    if (name.contains(key)) return kTheaterConfigs[key]!;
  }
  return const TheaterConfig(5, ['Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 10.7744, 106.6953, '116 Nguyễn Du, Quận 1');
}

Future<void> updateTheaterSizesAndSeedShowtimes() async {
  final firestore = FirebaseFirestore.instance;

  // 1. Gán lại size (mặc định) để không bị lỗi màn hình cũ, và log ra config
  print('Updating theater configs and seeding rooms...');
  final theaterSnap = await firestore.collection('theaters').get();
  
  for (final doc in theaterSnap.docs) {
    final name = doc.data()['name'] as String?;
    if (name == null) continue;
    
    // Gán Size tượng trưng (Large nếu >= 8 phòng, Medium nếu >= 6, Small nếu <= 5)
    final config = _getConfigForTheater(name);
    String size = config.roomCount >= 8 ? 'Large' : (config.roomCount >= 6 ? 'Medium' : 'Small');
    
    // Cập nhật size, toạ độ chuẩn và địa chỉ cho Rạp
    await doc.reference.update({
      'size': size,
      'lat': config.lat,
      'lng': config.lng,
      'address': config.address,
    });
    print('Configured $name -> $size (${config.roomCount} rooms)');

    // SEED ROOMS: Xóa phòng cũ và tạo phòng mới đúng chuẩn
    final roomsSnap = await firestore.collection('rooms').where('theaterName', isEqualTo: name).get();
    for (var rDoc in roomsSnap.docs) {
      await rDoc.reference.delete();
    }
    
    for (int r = 0; r < config.roomCount; r++) {
      final format = config.roomLayouts[r];
      await firestore.collection('rooms').add({
        'theaterName': name,
        'name': 'Rạp ${r + 1}',
        'roomFormat': format,
        'seatLayoutKind': seatLayoutKindToString(seatLayoutKindForFormat(format)),
        'standardRows': 10,
        'vipRows': format == 'VIP' || format == 'IMAX' || format == 'Premium' ? 2 : 0,
        'sweetboxRows': format == 'Couple' ? 2 : 0,
        'seatsPerRow': 12,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  // 2. Seed Showtimes
  print('Seeding random showtimes...');
  final movieSnap = await firestore.collection('movies').where('status', isEqualTo: 'Đang chiếu').get();
  if (movieSnap.docs.isEmpty) {
    print('No movies currently showing to seed showtimes.');
    return;
  }

  final random = Random();
  const languages = ['Phụ đề', 'Lồng tiếng'];

  // Seed cho 5 ngày tới
  for (int i = 0; i < 5; i++) {
    final date = DateTime.now().add(Duration(days: i));

    for (final theaterDoc in theaterSnap.docs) {
      final theaterName = theaterDoc.data()['name'] as String;
      final config = _getConfigForTheater(theaterName);

      final movies = movieSnap.docs.toList()..shuffle();
      if (movies.isEmpty) continue;

      // Mỗi phòng sẽ chiếu 5 suất một ngày (từ 8h sáng tới 20-21h tối)
      for (int r = 0; r < config.roomCount; r++) {
        // Chia đều phim cho các phòng. Ví dụ 10 phòng, 3 phim => mỗi phim được chia 3-4 phòng khác nhau.
        final movie = movies[r % movies.length];
        final format = config.roomLayouts[r];
        final language = languages[random.nextInt(languages.length)];

        for (int showNum = 0; showNum < 5; showNum++) {
          final hour = 8 + (showNum * 3) + random.nextInt(2); // Khoảng 8h, 11h, 14h, 17h, 20h
          final minute = random.nextInt(4) * 15; // 0, 15, 30, 45
          final showAt = DateTime(date.year, date.month, date.day, hour, minute);

          await firestore.collection('showtimes').add({
            'movieId': movie.id,
            'theaterName': theaterName,
            'showAt': Timestamp.fromDate(showAt),
            'date': Showtime.isoDate(showAt),
            'time': Showtime.hhmm(showAt),
            'roomName': 'Rạp ${r + 1}',
            'roomFormat': format,
            'language': language,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
    }
  }
  print('Showtimes and Rooms seeded successfully!');
}

/// Migration one-off: backfill field 'showAt' (Timestamp) cho các tài liệu
/// 'showtimes' cũ chưa có field này, parse từ 'date'/'time' string (cả 2 định
/// dạng từng tồn tại: ISO 'yyyy-MM-dd' và nhãn tiếng Việt 'Thứ 4, dd/MM' - xem
/// models/showtime.dart Showtime.parseLegacyDateTime). Dùng WriteBatch theo
/// lô 400 để tránh giới hạn 500 thao tác/batch của Firestore.
Future<void> migrateShowtimesToTimestamp() async {
  final firestore = FirebaseFirestore.instance;
  print('Migrating showtimes to showAt Timestamp...');

  final snap = await firestore.collection('showtimes').get();
  final toMigrate = snap.docs.where((doc) => doc.data()['showAt'] == null).toList();
  if (toMigrate.isEmpty) {
    print('No showtimes need migration.');
    return;
  }

  int migrated = 0, skipped = 0;
  for (var i = 0; i < toMigrate.length; i += 400) {
    final chunk = toMigrate.skip(i).take(400);
    final batch = firestore.batch();
    for (final doc in chunk) {
      final data = doc.data();
      final parsed = Showtime.parseLegacyDateTime(data['date'] as String?, data['time'] as String?);
      if (parsed == null) {
        skipped++;
        continue;
      }
      batch.update(doc.reference, {
        'showAt': Timestamp.fromDate(parsed),
        'date': Showtime.isoDate(parsed),
        'time': Showtime.hhmm(parsed),
      });
      migrated++;
    }
    await batch.commit();
  }
  print('Migrated $migrated showtimes, skipped $skipped (unparseable date/time).');
}

/// Mapping định dạng phòng cũ sang hệ 9 định dạng cuối cùng của Stella Cinema
/// (xem models/room_layout.dart kRoomFormatSpecs: Standard/Couple/VIP/Premium/
/// Dolby Atmos/Onyx LED/IMAX/ScreenX/4DX). Bao gồm cả tên gốc trước khi có hệ
/// thống định dạng riêng ('2D Phụ đề', 'GoldClass'...) lẫn tên trung gian
/// ('Standard (2D/3D)', 'Gold Class', 'Sweetbox'...) từng dùng ở 1 phiên bản
/// migration trước đó - đề phòng dữ liệu đã chạy migration cũ 1 lần rồi.
/// '2D Phụ đề'/'2D Lồng tiếng' xưa vốn là 2 định dạng riêng biệt - giờ gộp về
/// 1 định dạng phòng 'Standard' + suy ra field 'language' tương ứng cho
/// showtimes (phòng không còn giữ ngôn ngữ).
const Map<String, String> _kLegacyFormatToNewFormat = {
  // Tên gốc (trước khi có hệ thống định dạng riêng của Stella Cinema).
  '2D Phụ đề': 'Standard',
  '2D Lồng tiếng': 'Standard',
  'VIP': 'VIP',
  'GoldClass': 'VIP',
  "L'amour": 'Couple',
  'Premium': 'Premium',
  'IMAX': 'IMAX',
  '4DX': '4DX',
  'ScreenX': 'ScreenX',
  // Tên trung gian (đã từng migrate qua 1 lần, 12 định dạng brand thật).
  'Standard (2D/3D)': 'Standard',
  'Sweetbox': 'Couple',
  'Dolby Atmos': 'Dolby Atmos',
  'Ultra 4DX': '4DX',
  'STARIUM': 'IMAX',
  'Gold Class': 'VIP',
  'Premium Cinema': 'Premium',
  'Samsung Onyx Cinema LED': 'Onyx LED',
};

String? _legacyFormatToLanguage(String legacyFormat) {
  if (legacyFormat == '2D Phụ đề') return 'Phụ đề';
  if (legacyFormat == '2D Lồng tiếng') return 'Lồng tiếng';
  return null; // Định dạng cũ khác không mã hoá ngôn ngữ trong tên - để mặc định.
}

/// Migration one-off: đổi tên định dạng phòng cũ sang hệ Stella Cinema mới
/// cho cả 'rooms' và 'showtimes'. Chỉ đổi field 'roomFormat' (+ 'seatLayoutKind'
/// cho rooms, + 'language' cho showtimes nếu suy luận được từ tên cũ) - KHÔNG
/// đụng standardRows/vipRows/sweetboxRows/seatsPerRow đã cấu hình thật, tránh
/// ghi đè cấu hình phòng theater_manager đã tinh chỉnh tay.
Future<void> migrateRoomFormatsToStellaBranding() async {
  final firestore = FirebaseFirestore.instance;
  print('Migrating room formats to Stella Cinema branding...');

  final roomsSnap = await firestore.collection('rooms').get();
  final roomsToMigrate = roomsSnap.docs.where((doc) {
    final format = doc.data()['roomFormat'] as String?;
    return format != null && _kLegacyFormatToNewFormat.containsKey(format);
  }).toList();

  int roomsMigrated = 0;
  for (var i = 0; i < roomsToMigrate.length; i += 400) {
    final chunk = roomsToMigrate.skip(i).take(400);
    final batch = firestore.batch();
    for (final doc in chunk) {
      final oldFormat = doc.data()['roomFormat'] as String;
      final newFormat = _kLegacyFormatToNewFormat[oldFormat]!;
      batch.update(doc.reference, {
        'roomFormat': newFormat,
        'seatLayoutKind': seatLayoutKindToString(seatLayoutKindForFormat(newFormat)),
      });
      roomsMigrated++;
    }
    await batch.commit();
  }

  final showtimesSnap = await firestore.collection('showtimes').get();
  final showtimesToMigrate = showtimesSnap.docs.where((doc) {
    final format = doc.data()['roomFormat'] as String?;
    return format != null && _kLegacyFormatToNewFormat.containsKey(format);
  }).toList();

  int showtimesMigrated = 0;
  for (var i = 0; i < showtimesToMigrate.length; i += 400) {
    final chunk = showtimesToMigrate.skip(i).take(400);
    final batch = firestore.batch();
    for (final doc in chunk) {
      final oldFormat = doc.data()['roomFormat'] as String;
      final newFormat = _kLegacyFormatToNewFormat[oldFormat]!;
      final language = _legacyFormatToLanguage(oldFormat);
      batch.update(doc.reference, {
        'roomFormat': newFormat,
        if (language != null && doc.data()['language'] == null) 'language': language,
      });
      showtimesMigrated++;
    }
    await batch.commit();
  }

  print('Migrated $roomsMigrated rooms and $showtimesMigrated showtimes to Stella Cinema format branding.');
}
