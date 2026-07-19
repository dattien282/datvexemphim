import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../../../providers/theaters_provider.dart';
import '../../../models/showtime.dart';
import '../../theater_manager/screens/room_management_screen.dart' show roomFormatColor;
import 'seat_booking_screen.dart';

class ShowtimeSelectionScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> movieData;
  const ShowtimeSelectionScreen({super.key, required this.movieData});

  @override
  ConsumerState<ShowtimeSelectionScreen> createState() => _ShowtimeSelectionScreenState();
}

class _ShowtimeSelectionScreenState extends ConsumerState<ShowtimeSelectionScreen> {
  // Khoá nhóm ngày dạng 'yyyy-MM-dd' suy ra từ showAt thật của suất chiếu -
  // không dùng trực tiếp field 'date' thô của Firestore vì tài liệu cũ có thể
  // vẫn ở định dạng string khác (xem models/showtime.dart).
  String? _selectedDateKey;
  String? _selectedTheater;
  String? _selectedTime;
  // TẤT CẢ suất chiếu thật (mọi rạp) khớp phim đã chọn - tải 1 lần, sau đó lọc
  // theo rạp/ngày cục bộ khi người dùng bấm mở từng rạp (accordion), thay vì
  // phải chọn 1 rạp qua dropdown trước rồi mới truy vấn lại như trước đây.
  // Đổi UX cho khớp trải nghiệm Galaxy Cinema thật: chọn ngày trước, sau đó
  // liệt kê TẤT CẢ rạp dạng co giãn (ExpansionTile), mỗi rạp tự lọc suất theo
  // ngày đang chọn khi mở ra.
  List<Showtime>? _allShowtimes;
  Showtime? _selectedShowtime;

  @override
  void initState() {
    super.initState();
    _loadAllShowtimes();
  }

  Future<void> _loadAllShowtimes() async {
    final movieTitle = widget.movieData['title'];
    final snap = await FirebaseFirestore.instance
        .collection('showtimes')
        .where('movieTitle', isEqualTo: movieTitle)
        .where('status', isEqualTo: 'active')
        .get();
    if (!mounted) return;
    final now = DateTime.now();
    final showtimes = snap.docs
        .map((d) => Showtime.fromMap(d.id, d.data()))
        .where((s) => s.showAt != null && s.showAt!.isAfter(now))
        .toList()
      ..sort((a, b) => a.showAt!.compareTo(b.showAt!));
    setState(() {
      _allShowtimes = showtimes;
      _selectedDateKey ??= Showtime.isoDate(Showtime.logicalShowDate(now));
    });
  }

  void _selectShowtime(Showtime s, String theaterName) {
    setState(() {
      _selectedShowtime = s;
      _selectedTheater = theaterName;
      _selectedTime = Showtime.hhmm(s.showAt!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theaterNames = ref.watch(theaterNamesProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A0A),
        elevation: 0,
        centerTitle: true,
        title: const Text('CHỌN LỊCH CHIẾU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    widget.movieData['posterUrl'] ?? '',
                    width: 60, height: 86, fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(width: 60, height: 86, color: const Color(0xFF222232), child: const Icon(Icons.movie, color: Colors.white24)),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.movieData['title'] ?? 'Phim bom tấn', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Text(widget.movieData['genre'] ?? 'Hành động', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Tab chọn NGÀY - luôn hiện ở đầu, không phụ thuộc việc đã mở rạp nào
          // (khớp thứ tự thao tác thật: khách chọn ngày trước, rồi mới tìm rạp).
          if (_allShowtimes != null) _buildDateTabs(),

          const Divider(color: Colors.white12, height: 24),

          // Danh sách TẤT CẢ rạp dạng co giãn - mỗi rạp tự lọc + gom nhóm suất
          // chiếu theo ngày đang chọn khi người dùng bấm mở ra.
          Expanded(
            child: _allShowtimes == null
                ? const Center(child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2))
                : theaterNames.isEmpty
                    ? const Center(child: Text('Chưa có rạp nào được cấu hình.', style: TextStyle(color: Colors.white38, fontSize: 13)))
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: theaterNames.length,
                        separatorBuilder: (context, index) => const Divider(color: Colors.white12, height: 1),
                        itemBuilder: (context, index) => _buildTheaterPanel(theaterNames[index]),
                      ),
          ),

          // NÚT ĐI TIẾP SANG CHỌN GHẾ
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: _selectedShowtime == null ? null : _goToSeatBooking,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, disabledBackgroundColor: Colors.white10, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('TIẾP TỤC CHỌN GHẾ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _goToSeatBooking() {
    // Đóng gói toàn bộ thông tin lịch trình truyền tiếp sang file sơ đồ ghế
    final Map<String, dynamic> completeMovieData = Map.from(widget.movieData);
    completeMovieData['selectedTheater'] = _selectedTheater;
    completeMovieData['selectedTime'] = _selectedTime;
    final s = _selectedShowtime!;
    completeMovieData['showtimeId'] = s.id;
    completeMovieData['priceStandard'] = s.priceStandard;
    completeMovieData['priceVip'] = s.priceVip;
    completeMovieData['roomName'] = s.roomName;
    completeMovieData['roomFormat'] = s.roomFormat;
    if (s.seatMapVersionId != null) completeMovieData['seatMapVersionId'] = s.seatMapVersionId;
    if (s.dynamicSurchargePercent > 0) completeMovieData['dynamicSurchargePercent'] = s.dynamicSurchargePercent;
    completeMovieData['language'] = s.language;
    completeMovieData['sessionType'] = s.sessionType;
    if (s.showAt != null) {
      // showAt truyền dạng millis (Map vẫn Map<String,dynamic>, không đổi hẳn
      // sang model ở seat_booking_screen.dart) để tính giờ/ngày thật ở đó
      // thay vì string-match như trước.
      completeMovieData['showAt'] = s.showAt!.millisecondsSinceEpoch;
      completeMovieData['selectedDate'] =
          '${Showtime.vietnameseWeekday(s.showAt!.weekday)}, ${DateFormat('dd/MM').format(s.showAt!)}';
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => SeatBookingScreen(movieData: completeMovieData)),
    );
  }

  Widget _buildDateTabs() {
    final now = DateTime.now();
    final logicalToday = Showtime.logicalShowDate(now);
    final todayMidnight = DateTime(logicalToday.year, logicalToday.month, logicalToday.day);
    final dateKeys = List.generate(7, (i) => Showtime.isoDate(todayMidnight.add(Duration(days: i))));

    return SizedBox(
      height: 62,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: dateKeys.length,
        itemBuilder: (context, index) {
          final dateKey = dateKeys[index];
          final sampleDate = todayMidnight.add(Duration(days: index));
          final weekdayLabel = index == 0 ? 'Hôm nay' : Showtime.vietnameseWeekday(sampleDate.weekday);
          final isSelected = _selectedDateKey == dateKey;

          return GestureDetector(
            onTap: () => setState(() {
              _selectedDateKey = dateKey;
              _selectedShowtime = null;
              _selectedTheater = null;
              _selectedTime = null;
            }),
            child: Container(
              width: 76,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: isSelected ? Colors.amber : const Color(0xFF0A0A0A),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(weekdayLabel, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 2),
                  Text(DateFormat('dd/MM').format(sampleDate), style: TextStyle(color: isSelected ? Colors.black87 : Colors.white38, fontSize: 11)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Panel co giãn (ExpansionTile) cho 1 rạp - chỉ lọc/gom nhóm suất chiếu của
  // đúng rạp này + ngày đang chọn khi người dùng bấm mở ra (dữ liệu suất
  // chiếu đã tải sẵn hết 1 lần ở _loadAllShowtimes, không query lại Firestore
  // mỗi lần mở/đóng 1 rạp).
  Widget _buildTheaterPanel(String theaterName) {
    final showtimesForTheaterAndDate = (_allShowtimes ?? []).where((s) {
      if (s.theaterName != theaterName || s.showAt == null) return false;
      return Showtime.isoDate(Showtime.logicalShowDate(s.showAt!)) == _selectedDateKey;
    }).toList();

    final hasSelectionInThisTheater = _selectedTheater == theaterName;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: hasSelectionInThisTheater,
        iconColor: Colors.amber,
        collapsedIconColor: Colors.white54,
        title: Text(theaterName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
        childrenPadding: const EdgeInsets.only(bottom: 14),
        children: [
          if (showtimesForTheaterAndDate.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Rạp này chưa có suất chiếu cho ngày đã chọn.', style: TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic)),
              ),
            )
          else
            ..._buildFormatGroups(showtimesForTheaterAndDate, theaterName),
        ],
      ),
    );
  }

  // Gom nhóm theo RoomFormat + ProjectionFormat + Language giống Galaxy
  // Cinema, vẽ lưới nút giờ chiếu cho từng nhóm.
  List<Widget> _buildFormatGroups(List<Showtime> showtimesForDate, String theaterName) {
    final now = DateTime.now();
    final durationStr = widget.movieData['duration'] as String? ?? '120';
    final match = RegExp(r'\d+').firstMatch(durationStr);
    final durationMins = match != null ? int.parse(match.group(0)!) : 120;

    // Gom nhóm theo ĐÚNG 3 trục: RoomFormat + ProjectionFormat + Language.
    // Trước đây khoá gộp chỉ có projectionFormat + language, THIẾU roomFormat
    // - khiến 1 phòng Standard và 1 phòng VIP cùng chiếu bản "2D Phụ đề" bị
    // dồn chung vào 1 nhóm hiển thị (dù giá vé/loại ghế khác hẳn nhau), và
    // màu nhóm chỉ phản ánh đúng định dạng của suất đầu tiên trong nhóm.
    final grouped = <String, List<Showtime>>{};
    for (final s in showtimesForDate) {
      // Ưu tiên projectionFormat thật của suất chiếu (VD "IMAX 3D") nếu có -
      // suất chiếu cũ chưa có field này thì fallback về cách suy đoán cũ từ
      // roomFormat (luôn coi là bản 2D).
      final formatName = s.projectionFormat ?? (s.roomFormat == 'Standard' ? '2D' : s.roomFormat.toUpperCase());
      final groupKey = '${s.roomFormat}|$formatName|${s.language}';
      grouped.putIfAbsent(groupKey, () => []).add(s);
    }

    return grouped.entries.map((entry) {
      final groupShowtimes = entry.value;
      final sample = groupShowtimes.first;
      final formatColor = roomFormatColor(sample.roomFormat);
      // Nhãn hiển thị: "STANDARD" không cần lặp lại (đã ngầm hiểu là phòng
      // thường), các định dạng khác (VIP, VIP - Laurus, IMAX...) hiện rõ tên
      // để phân biệt - khớp cách Galaxy Cinema hiển thị "VIP – LAURUS 2D".
      final sampleFormatName = sample.projectionFormat ?? (sample.roomFormat == 'Standard' ? '2D' : sample.roomFormat.toUpperCase());
      final groupName = sample.roomFormat == 'Standard'
          ? '$sampleFormatName ${sample.language}'
          : '${sample.roomFormat.toUpperCase()} $sampleFormatName ${sample.language}';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 10),
            child: Row(
              children: [
                Icon(Icons.movie_filter_rounded, color: formatColor, size: 14),
                const SizedBox(width: 6),
                Text(groupName, style: TextStyle(color: formatColor, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5)),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.0),
            itemCount: groupShowtimes.length,
            itemBuilder: (context, index) {
              final s = groupShowtimes[index];
              final time = Showtime.hhmm(s.showAt!);

              // Dự báo giờ ra về (thời lượng + 10p quảng cáo)
              final endTime = s.showAt!.add(Duration(minutes: durationMins + 10));
              final endTimeStr = Showtime.hhmm(endTime);

              // Đóng quầy sau khi chiếu được 15 phút
              final isPast = s.showAt!.isBefore(now.subtract(const Duration(minutes: 15)));

              final isSelected = _selectedShowtime?.id == s.id;
              return GestureDetector(
                onTap: isPast ? null : () => _selectShowtime(s, theaterName),
                child: Container(
                  decoration: BoxDecoration(
                    color: isPast ? Colors.white.withValues(alpha: 0.05) : (isSelected ? Colors.amber : const Color(0xFF0A0A0A)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSelected && !isPast ? Colors.white : Colors.white.withValues(alpha: 0.05)),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(time, style: TextStyle(
                        color: isPast ? Colors.white24 : (isSelected ? Colors.black : Colors.white),
                        fontWeight: FontWeight.bold, fontSize: 13,
                        decoration: isPast ? TextDecoration.lineThrough : null,
                      )),
                      const SizedBox(height: 2),
                      Text('~ $endTimeStr', style: TextStyle(
                        color: isPast ? Colors.white12 : (isSelected ? Colors.black54 : Colors.white54),
                        fontSize: 9
                      )),
                      if (s.sessionType != 'Standard' && !isPast) ...[
                        const SizedBox(height: 2),
                        Text(s.sessionType, style: TextStyle(color: isSelected ? Colors.black54 : Colors.white38, fontSize: 8, fontStyle: FontStyle.italic)),
                      ]
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      );
    }).toList();
  }
}
