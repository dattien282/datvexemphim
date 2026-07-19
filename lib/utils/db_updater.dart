import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/showtime.dart';
import '../models/room_layout.dart';
import '../models/session_type.dart';

class TheaterConfig {
  final int roomCount;
  final List<String> roomLayouts; // Format của từng phòng từ Rạp 1 đến Rạp N
  final double lat;
  final double lng;
  final String address;
  const TheaterConfig(this.roomCount, this.roomLayouts, this.lat, this.lng, this.address);
}

final Map<String, TheaterConfig> kTheaterConfigs = {
  'Tân Phú': const TheaterConfig(8, ['Dolby Atmos', 'Couple', 'Gold Class', 'Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 10.8015, 106.6166, '30 Bờ Bao Tân Thắng, Sơn Kỳ, Tân Phú, Thành phố Hồ Chí Minh'),
  'Crescent': const TheaterConfig(7, ['VIP - Laurus', 'Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard'], 10.7296, 106.7208, '101 Tôn Dật Tiên, Tân Phú, Quận 7, Thành phố Hồ Chí Minh'),
  'Gigamall': const TheaterConfig(10, ['IMAX', 'Starium', 'Dolby Atmos', 'Gold Class', 'Couple', 'VIP - Laurus', 'VIP - Lagom', 'Standard', 'Standard', 'Standard'], 10.8276, 106.7214, '240-242 Phạm Văn Đồng, Hiệp Bình Chánh, Thủ Đức, Thành phố Hồ Chí Minh'),
  'Landmark': const TheaterConfig(9, ['IMAX', 'VIP - Laurus', 'VIP - Lagom', 'Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard'], 10.7950, 106.7218, 'Vinhomes Central Park, 720A Điện Biên Phủ, Phường 22, Bình Thạnh, Thành phố Hồ Chí Minh'),
  'Vạn Hạnh': const TheaterConfig(8, ['4DX', 'Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 10.7758, 106.6690, '11 Sư Vạn Hạnh, Phường 12, Quận 10, Thành phố Hồ Chí Minh'),
  'Estella': const TheaterConfig(6, ['VIP - Lagom', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard'], 10.8016, 106.7397, '88 Song Hành, An Phú, Thủ Đức, Thành phố Hồ Chí Minh'),
  'Nguyễn Du': const TheaterConfig(5, ['Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 10.7744, 106.6953, '116 Nguyễn Du, Bến Thành, Quận 1, Thành phố Hồ Chí Minh'),
  'Mipec': const TheaterConfig(7, ['IMAX', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 21.0425, 105.8679, '2 Long Biên 2, Ngọc Lâm, Long Biên, Hà Nội'),
  'Royal': const TheaterConfig(11, ['IMAX', 'Starium', '4DX', 'Dolby Atmos', 'Gold Class', 'VIP - Laurus', 'Couple', 'Premium', 'Standard', 'Standard', 'Standard'], 21.0028, 105.8152, '72A Nguyễn Trãi, Thượng Đình, Thanh Xuân, Hà Nội'),
  'Times': const TheaterConfig(10, ['IMAX', 'ScreenX', 'Gold Class', 'Couple', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard', 'Standard'], 20.9959, 105.8669, '458 Minh Khai, Vĩnh Phú, Hai Bà Trưng, Hà Nội'),
  'Cần Thơ': const TheaterConfig(6, ['Couple', 'VIP - Lagom', 'Premium', 'Standard', 'Standard', 'Standard'], 10.0345, 105.7865, '1 Đại lộ Hòa Bình, Tân An, Ninh Kiều, Cần Thơ'),
  'Đà Nẵng': const TheaterConfig(7, ['IMAX', 'Dolby Atmos', 'Premium', 'Premium', 'Standard', 'Standard', 'Standard'], 16.0718, 108.2307, '910A Ngô Quyền, An Hải Bắc, Sơn Trà, Đà Nẵng'),
};

// Giá vé tham khảo theo từng định dạng phòng (đ) - phân khúc cao cấp hơn thì
// giá Standard/VIP nền cũng cao hơn, khớp mô hình giá thật của các hệ thống
// rạp (Gold Class/Starium/IMAX đắt hơn nhiều so với phòng Standard thường).
// [priceStandard, priceVip] - priceVip cũng là giá nền cho ghế đôi/ghế lớn
// (xem seatPrice() ở backend-payos/server.js: sweetbox = priceVip + 80000).
const Map<String, List<int>> _kFormatPricing = {
  'Standard': [80000, 110000],
  'Couple': [80000, 120000],
  'VIP': [90000, 140000],
  'VIP - Laurus': [95000, 160000],
  'VIP - Lagom': [90000, 150000],
  'Premium': [100000, 170000],
  'Dolby Atmos': [100000, 170000],
  'Onyx LED': [110000, 190000],
  'Gold Class': [150000, 250000],
  'IMAX': [110000, 150000],
  'ScreenX': [100000, 140000],
  '4DX': [150000, 180000],
  'Starium': [130000, 170000],
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
      // Dùng đúng preset hàng ghế của định dạng (kDefaultRoomFormatSpecs) thay vì
      // công thức cứng cũ (10 hàng thường + 2 hàng vip chỉ cho 3 định dạng) -
      // công thức cũ làm sai lệch layout với seatLayoutKind đã suy ra (VD
      // phòng Gold Class/VIP - Laurus toàn ghế lớn nhưng vẫn bị gán 10 hàng
      // ghế thường), và không hỗ trợ được các định dạng mới thêm vào.
      final spec = findRoomFormatSpec(format);
      await firestore.collection('rooms').add({
        'theaterName': name,
        'name': 'Rạp ${r + 1}',
        'roomFormat': format,
        'seatLayoutKind': seatLayoutKindToString(seatLayoutKindForFormat(format)),
        'standardRows': spec?.standardRows ?? 10,
        'vipRows': spec?.vipRows ?? 0,
        'sweetboxRows': spec?.sweetboxRows ?? 0,
        'seatsPerRow': spec?.seatsPerRow ?? 12,
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
  // Dàn 6 khung giờ trải từ sáng sớm tới khuya (thay vì chỉ 5 khung gần như
  // trùng giờ hành chính) để sessionType tự suy ra (detectSessionType) phủ đủ
  // Morning/Late Morning/Afternoon/Prime Time/Evening/Midnight - đúng tinh
  // thần "đa dạng giờ chiếu" thay vì chỉ lặp lại vài khung gần giống nhau.
  const baseHours = [8, 10, 13, 16, 19, 22];

  // Seed cho 5 ngày tới
  for (int i = 0; i < 5; i++) {
    final date = DateTime.now().add(Duration(days: i));

    for (final theaterDoc in theaterSnap.docs) {
      final theaterName = theaterDoc.data()['name'] as String;
      final config = _getConfigForTheater(theaterName);

      // Giới hạn số phim KHÁC NHAU được chiếu ở mỗi rạp/ngày, thay vì dùng
      // toàn bộ danh sách phim - trước đây khi số phim đang chiếu (thường
      // 15-20+) nhiều hơn số phòng của rạp (5-11), công thức `movies[r %
      // movies.length]` gán mỗi phòng 1 phim RIÊNG BIỆT không trùng ai, nên 1
      // phim chỉ bao giờ xuất hiện ở đúng 1 định dạng/1 rạp - không đúng thực
      // tế rạp phim (phim hot luôn chiếu song song nhiều định dạng: 2D
      // Standard + VIP + IMAX...). Giới hạn còn ~roomCount/2 phim để mỗi phim
      // tự lặp lại qua ÍT NHẤT 2 phòng/định dạng khác nhau.
      final shuffledMovies = movieSnap.docs.toList()..shuffle();
      if (shuffledMovies.isEmpty) continue;
      final movieCap = (config.roomCount / 2).ceil().clamp(2, 6);
      final movies = shuffledMovies.take(movieCap).toList();

      for (int r = 0; r < config.roomCount; r++) {
        // Chia đều phim cho các phòng - cùng 1 phim rơi vào nhiều phòng/định
        // dạng khác nhau nhờ movieCap giới hạn ở trên.
        final movie = movies[r % movies.length];
        final movieData = movie.data();
        final movieTitle = movieData['title'] as String? ?? '';
        final movieReleaseDate = parseReleaseDate(movieData['releaseDate'] as String?);
        final format = config.roomLayouts[r];
        final language = languages[random.nextInt(languages.length)];
        final pricing = _kFormatPricing[format] ?? const [80000, 110000];
        // Phòng hỗ trợ nhiều tổ hợp trình chiếu/âm thanh (VD IMAX chiếu được
        // cả IMAX 2D lẫn IMAX 3D) - random giữa các tổ hợp có sẵn theo từng
        // suất để lịch chiếu thật sự đa dạng định dạng trong ngày, khớp cách
        // các cụm rạp thật xếp lịch (không phải suất nào cũng cùng 1 bản).
        final capabilities = defaultCapabilitiesForFormat(format);

        for (int showNum = 0; showNum < baseHours.length; showNum++) {
          final hour = (baseHours[showNum] + random.nextInt(2)).clamp(6, 23);
          final minute = random.nextInt(4) * 15; // 0, 15, 30, 45
          final showAt = DateTime(date.year, date.month, date.day, hour, minute);
          final capability = capabilities[random.nextInt(capabilities.length)];

          await firestore.collection('showtimes').add({
            'movieTitle': movieTitle,
            'theaterName': theaterName,
            'showAt': Timestamp.fromDate(showAt),
            'date': Showtime.isoDate(showAt),
            'time': Showtime.hhmm(showAt),
            'roomName': 'Rạp ${r + 1}',
            'roomFormat': format,
            'projectionFormat': capability.projectionFormat,
            'soundFormat': capability.soundFormat,
            'language': language,
            'sessionType': detectSessionType(showAt, movieReleaseDate),
            'priceStandard': pricing[0],
            'priceVip': pricing[1],
            'status': 'active',
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
/// (xem models/room_layout.dart kDefaultRoomFormatSpecs: Standard/Couple/VIP/Premium/
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

/// Migration one-off (Giai đoạn H): chuyển 13 định dạng phòng chiếu từ hằng
/// số hardcode kDefaultRoomFormatSpecs (models/room_layout.dart) sang
/// collection Firestore 'room_formats' - để admin tự thêm/sửa/archive định
/// dạng qua AdminRoomFormatsScreen mà không cần sửa code + build lại app.
/// Chỉ seed nếu collection đang RỖNG (idempotent - chạy lại nhiều lần không
/// tạo trùng), không đụng gì tới 'rooms'/'showtimes' hiện có: chúng vẫn tham
/// chiếu roomFormat bằng TÊN (string) như trước, không đổi cách join.
Future<void> migrateRoomFormatsToFirestore() async {
  final firestore = FirebaseFirestore.instance;
  print('Seeding room_formats collection...');

  final existing = await firestore.collection('room_formats').limit(1).get();
  if (existing.docs.isNotEmpty) {
    print('room_formats đã có dữ liệu - bỏ qua seed để không tạo trùng.');
    return;
  }

  final batch = firestore.batch();
  for (final spec in kDefaultRoomFormatSpecs) {
    final ref = firestore.collection('room_formats').doc();
    batch.set(ref, spec.toMap());
  }
  await batch.commit();

  print('Seeded ${kDefaultRoomFormatSpecs.length} room formats vào Firestore.');
}

/// Dữ liệu demo cho 3 collection hoàn toàn trống nếu chưa ai từng dùng thật:
/// 'incidents' (Báo cáo Sự cố - staff gửi/manager xem), 'shifts' (Smart
/// Roster - manager phân/staff xem), 'attendance_logs' (Điểm danh ca làm).
/// Trước đây 3 màn hình này luôn hiện "chưa có dữ liệu" dù UI đã xây xong,
/// khiến demo trông trống trải dù tính năng đã hoạt động đầy đủ.
///
/// Dùng ĐÚNG tài khoản staff/theater_manager thật đã có sẵn trong Firestore
/// (gán theo assignedTheater) thay vì bịa uid giả - để tên hiện đúng thay vì
/// "Unknown" (Smart Roster tra `users/{uid}` để hiện tên), và để tài khoản
/// staff thật đăng nhập vào đúng thấy được ca/lịch sử của chính mình (Staff
/// dashboard lọc theo uid đang đăng nhập). Idempotent theo từng rạp: bỏ qua
/// nếu rạp đó đã có sẵn incidents/shift hôm nay, không tạo trùng mỗi lần bấm
/// lại; và bỏ qua hẳn rạp nào chưa có tài khoản staff nào (không seed
/// shifts/attendance dở dang chỉ để trống staffIds).
Future<void> seedStaffManagerDemoData() async {
  final firestore = FirebaseFirestore.instance;
  print('Seeding demo data cho Staff/Theater Manager...');

  final theaterSnap = await firestore.collection('theaters').get();
  final now = DateTime.now();
  String pad2(int n) => n.toString().padLeft(2, '0');
  final todayStr = '${now.year}-${pad2(now.month)}-${pad2(now.day)}';

  const incidentSamples = [
    {'type': 'Hết bắp nước', 'description': 'Quầy bắp nước hết vị phô mai, cần nhập thêm cho suất chiều.', 'status': 'pending', 'hoursAgo': 1},
    {'type': 'Hỏng ghế', 'description': 'Ghế C5 phòng 1 bị lỏng tay vịn, cần thợ kiểm tra trước suất tối.', 'status': 'resolved', 'hoursAgo': 26},
    {'type': 'Vệ sinh', 'description': 'Sảnh chờ suất 19h cần dọn thêm rác sau giờ cao điểm cuối tuần.', 'status': 'pending', 'hoursAgo': 4},
  ];

  int theatersSeeded = 0;
  for (final theaterDoc in theaterSnap.docs) {
    final theaterName = theaterDoc.data()['name'] as String?;
    if (theaterName == null) continue;

    final staffSnap = await firestore
        .collection('users')
        .where('role', whereIn: ['staff', 'theater_manager'])
        .where('assignedTheater', isEqualTo: theaterName)
        .get();
    if (staffSnap.docs.isEmpty) continue; // Không có ai để gán - bỏ qua rạp này.
    final staffOnly = staffSnap.docs.where((d) => d.data()['role'] == 'staff').toList();
    final assignee = staffOnly.isNotEmpty ? staffOnly.first : staffSnap.docs.first;
    final assigneeEmail = assignee.data()['email'] as String? ?? 'staff@stellacinema.vn';

    // 1. Incidents demo.
    final existingIncidents = await firestore.collection('incidents').where('theater', isEqualTo: theaterName).limit(1).get();
    if (existingIncidents.docs.isEmpty) {
      final batch = firestore.batch();
      for (final sample in incidentSamples) {
        final ref = firestore.collection('incidents').doc();
        final createdAt = now.subtract(Duration(hours: sample['hoursAgo'] as int));
        batch.set(ref, {
          'theater': theaterName,
          'reporterEmail': assigneeEmail,
          'type': sample['type'],
          'description': sample['description'],
          'status': sample['status'],
          'createdAt': Timestamp.fromDate(createdAt),
          if (sample['status'] == 'resolved') 'resolvedAt': Timestamp.fromDate(now.subtract(const Duration(hours: 20))),
        });
      }
      await batch.commit();
    }

    // 2. Shifts demo (hôm nay, đủ 3 ca, gán tất cả staff có sẵn của rạp vào ca sáng).
    final existingShifts = await firestore
        .collection('shifts')
        .where('theater', isEqualTo: theaterName)
        .where('date', isEqualTo: todayStr)
        .limit(1)
        .get();
    if (existingShifts.docs.isEmpty) {
      final morningStaffIds = staffOnly.map((d) => d.id).toList();
      final batch = firestore.batch();
      for (final shiftType in ['morning', 'afternoon', 'night']) {
        final ref = firestore.collection('shifts').doc();
        batch.set(ref, {
          'theater': theaterName,
          'date': todayStr,
          'shiftType': shiftType,
          'staffIds': shiftType == 'morning' ? morningStaffIds : <String>[],
        });
      }
      await batch.commit();
    }

    // 3. Attendance demo (1 nhân viên đã vào ca sáng hôm nay, chưa ra ca).
    final existingAttendance = await firestore
        .collection('attendance_logs')
        .where('theater', isEqualTo: theaterName)
        .where('date', isEqualTo: todayStr)
        .limit(1)
        .get();
    if (existingAttendance.docs.isEmpty && staffOnly.isNotEmpty) {
      final staffDoc = staffOnly.first;
      await firestore.collection('attendance_logs').add({
        'uid': staffDoc.id,
        'displayName': staffDoc.data()['displayName'] ?? staffDoc.data()['email'] ?? 'Nhân viên',
        'email': staffDoc.data()['email'] ?? '',
        'theater': theaterName,
        'date': todayStr,
        'checkInTime': Timestamp.fromDate(DateTime(now.year, now.month, now.day, 8, 2)),
        'checkOutTime': null,
        'status': 'check_in',
      });
    }

    theatersSeeded++;
  }

  print('Đã seed demo data (sự cố/ca làm/điểm danh) cho $theatersSeeded rạp có sẵn tài khoản staff.');
}
