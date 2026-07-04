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
  String? _selectedTheater;
  // Khoá nhóm ngày dạng 'yyyy-MM-dd' suy ra từ showAt thật của suất chiếu -
  // không dùng trực tiếp field 'date' thô của Firestore vì tài liệu cũ có thể
  // vẫn ở định dạng string khác (xem models/showtime.dart).
  String? _selectedDateKey;
  String? _selectedTime;
  // Suất chiếu thật (do theater_manager tạo trong collection 'showtimes')
  // khớp rạp + phim đã chọn. null = chưa tra cứu; [] = tra cứu xong, không có.
  List<Showtime>? _realShowtimes;
  Showtime? _selectedShowtime;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _loadRealShowtimes(String theater) async {
    setState(() {
      _realShowtimes = null;
      _selectedShowtime = null;
      _selectedDateKey = null;
      _selectedTime = null;
    });
    final movieTitle = widget.movieData['title'];
    final snap = await FirebaseFirestore.instance
        .collection('showtimes')
        .where('theaterName', isEqualTo: theater)
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
      _realShowtimes = showtimes;
      if (showtimes.isNotEmpty) {
        // Tự động chọn ngày đầu tiên có suất chiếu
        _selectedDateKey = Showtime.isoDate(showtimes.first.showAt!);
      }
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thông tin tóm tắt phim đang chọn
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    widget.movieData['posterUrl'] ?? '',
                    width: 70, height: 100, fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => Container(width: 70, height: 100, color: const Color(0xFF222232), child: const Icon(Icons.movie, color: Colors.white24)),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.movieData['title'] ?? 'Phim bom tấn', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                      const SizedBox(height: 6),
                      Text(widget.movieData['genre'] ?? 'Hành động', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 25),

            // 1. CHỌN CỤM RẠP CHIẾU
            const Text('1. CHỌN RẠP PHIM STELLA', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              dropdownColor: const Color(0xFF0A0A0A),
              decoration: InputDecoration(
                filled: true, fillColor: const Color(0xFF0A0A0A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              hint: const Text('Vui lòng chọn cụm rạp gần bạn', style: TextStyle(color: Colors.white38, fontSize: 13)),
              initialValue: _selectedTheater,
              items: theaterNames.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) {
                setState(() => _selectedTheater = val);
                if (val != null) _loadRealShowtimes(val);
              },
            ),
            const SizedBox(height: 25),

            if (_selectedTheater != null && _realShowtimes == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(color: Colors.amber, strokeWidth: 2)),
              )
            else if (_realShowtimes != null && _realShowtimes!.isNotEmpty)
              ..._buildRealShowtimeSelectors()
            else if (_selectedTheater != null && _realShowtimes != null && _realShowtimes!.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text(
                  'Rạp này hiện chưa có suất chiếu nào được lên lịch cho bộ phim này.',
                  style: TextStyle(color: Colors.redAccent, fontSize: 13),
                ),
              ),
            const SizedBox(height: 40),

            // NÚT ĐI TIẾP SANG CHỌN GHẾ
            SizedBox(
              width: double.infinity, height: 48,
              child: ElevatedButton(
                onPressed: (_selectedTheater == null || _selectedDateKey == null || _selectedTime == null) ? null : () {
                  // Đóng gói toàn bộ thông tin lịch trình truyền tiếp sang file sơ đồ ghế
                  final Map<String, dynamic> completeMovieData = Map.from(widget.movieData);
                  completeMovieData['selectedTheater'] = _selectedTheater;
                  completeMovieData['selectedTime'] = _selectedTime;
                  final s = _selectedShowtime;
                  if (s != null) {
                    completeMovieData['showtimeId'] = s.id;
                    completeMovieData['priceStandard'] = s.priceStandard;
                    completeMovieData['priceVip'] = s.priceVip;
                    completeMovieData['roomName'] = s.roomName;
                    completeMovieData['roomFormat'] = s.roomFormat;
                    completeMovieData['language'] = s.language;
                    completeMovieData['sessionType'] = s.sessionType;
                    if (s.showAt != null) {
                      // showAt truyền dạng millis (Map vẫn Map<String,dynamic>,
                      // không đổi hẳn sang model ở seat_booking_screen.dart) để
                      // tính giờ/ngày thật ở đó thay vì string-match như trước.
                      completeMovieData['showAt'] = s.showAt!.millisecondsSinceEpoch;
                      completeMovieData['selectedDate'] =
                          '${Showtime.vietnameseWeekday(s.showAt!.weekday)}, ${DateFormat('dd/MM').format(s.showAt!)}';
                    }
                  }

                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => SeatBookingScreen(movieData: completeMovieData)),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, disabledBackgroundColor: Colors.white10, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('TIẾP TỤC CHỌN GHẾ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Suất chiếu thật (từ collection 'showtimes' do theater_manager tạo) ──
  List<Widget> _buildRealShowtimeSelectors() {
    final showtimes = _realShowtimes!; // đã lọc showAt != null và sort tăng dần
    
    // Lấy ngày hôm nay theo quy tắc 6h sáng
    final now = DateTime.now();
    final logicalToday = Showtime.logicalShowDate(now);
    final todayMidnight = DateTime(logicalToday.year, logicalToday.month, logicalToday.day);
    
    // Tạo dải 7 ngày cố định
    final dateKeys = List.generate(7, (i) => Showtime.isoDate(todayMidnight.add(Duration(days: i))));
    
    // Khởi tạo _selectedDateKey nếu chưa chọn hoặc ngày cũ không nằm trong 7 ngày tới
    if (_selectedDateKey == null || !dateKeys.contains(_selectedDateKey)) {
      // Lưu ý: Dart cho phép gán biến thường trong build phase
      _selectedDateKey = dateKeys.first;
    }

    final showtimesForDate = showtimes.where((s) {
      if (s.showAt == null) return false;
      return Showtime.isoDate(Showtime.logicalShowDate(s.showAt!)) == _selectedDateKey;
    }).toList();

    // Tính thời lượng phim để dự báo giờ ra về
    final durationStr = widget.movieData['duration'] as String? ?? '120';
    final match = RegExp(r'\d+').firstMatch(durationStr);
    final durationMins = match != null ? int.parse(match.group(0)!) : 120;

    return [
      const Text('2. CHỌN NGÀY XEM PHIM', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
      const SizedBox(height: 12),
      SizedBox(
        height: 45,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: dateKeys.length,
          itemBuilder: (context, index) {
            final dateKey = dateKeys[index];
            final sampleDate = todayMidnight.add(Duration(days: index));
            final prefix = index == 0 ? 'Hôm nay' : Showtime.vietnameseWeekday(sampleDate.weekday);
            final label = '$prefix, ${DateFormat('dd/MM').format(sampleDate)}';
            final isSelected = _selectedDateKey == dateKey;
            
            return GestureDetector(
              onTap: () => setState(() {
                _selectedDateKey = dateKey;
                _selectedTime = null;
                _selectedShowtime = null;
              }),
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.amber : const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(label, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 25),
      const Text('3. CHỌN KHUNG GIỜ CHIẾU', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
      const SizedBox(height: 12),
      if (showtimesForDate.isEmpty)
        const Text('Hiện chưa có lịch chiếu nào được xếp cho ngày này.', style: TextStyle(color: Colors.white38, fontSize: 12, fontStyle: FontStyle.italic))
      else
        // Gom nhóm theo định dạng (roomFormat + language) giống Galaxy Cinema
        ...(() {
          final grouped = <String, List<Showtime>>{};
          for (final s in showtimesForDate) {
            final formatName = s.roomFormat == 'Standard' ? '2D' : s.roomFormat.toUpperCase();
            final groupName = formatName == '2D' ? '2D ${s.language}' : '$formatName - 2D ${s.language}';
            grouped.putIfAbsent(groupName, () => []).add(s);
          }
          
          return grouped.entries.map((entry) {
            final groupName = entry.key;
            final groupShowtimes = entry.value;
            final formatColor = roomFormatColor(groupShowtimes.first.roomFormat);
            
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 20, bottom: 12),
                  child: Row(
                    children: [
                      Icon(Icons.movie_filter_rounded, color: formatColor, size: 16),
                      const SizedBox(width: 6),
                      Text(groupName, style: TextStyle(color: formatColor, fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5)),
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
                      onTap: isPast ? null : () => setState(() {
                        _selectedTime = time;
                        _selectedShowtime = s;
                      }),
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
        }()),
    ];
  }
}
