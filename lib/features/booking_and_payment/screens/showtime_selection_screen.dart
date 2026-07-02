import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../providers/theaters_provider.dart';
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
  String? _selectedDate;
  String? _selectedTime;
  // Suất chiếu thật (do theater_manager tạo trong collection 'showtimes')
  // khớp rạp + phim đã chọn. null = chưa tra cứu; [] = tra cứu xong, không có.
  List<QueryDocumentSnapshot>? _realShowtimes;
  QueryDocumentSnapshot? _selectedShowtimeDoc;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _loadRealShowtimes(String theater) async {
    setState(() {
      _realShowtimes = null;
      _selectedShowtimeDoc = null;
      _selectedDate = null;
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
    final docs = snap.docs.toList()
      ..sort((a, b) {
        final ad = '${a['date']} ${a['time']}';
        final bd = '${b['date']} ${b['time']}';
        return ad.compareTo(bd);
      });
    setState(() {
      _realShowtimes = docs;
      if (docs.isNotEmpty) {
        // Tự động chọn ngày đầu tiên có suất chiếu
        final dates = docs.map((d) => (d.data() as Map)['date'] as String).toSet().toList()..sort();
        if (dates.isNotEmpty) {
          _selectedDate = dates.first;
        }
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
              value: _selectedTheater,
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
                onPressed: (_selectedTheater == null || _selectedDate == null || _selectedTime == null) ? null : () {
                  // Đóng gói toàn bộ thông tin lịch trình truyền tiếp sang file sơ đồ ghế
                  final Map<String, dynamic> completeMovieData = Map.from(widget.movieData);
                  completeMovieData['selectedTheater'] = _selectedTheater;
                  completeMovieData['selectedDate'] = _selectedDate;
                  completeMovieData['selectedTime'] = _selectedTime;
                  if (_selectedShowtimeDoc != null) {
                    final d = _selectedShowtimeDoc!.data() as Map<String, dynamic>;
                    completeMovieData['showtimeId'] = _selectedShowtimeDoc!.id;
                    completeMovieData['priceStandard'] = d['priceStandard'];
                    completeMovieData['priceVip'] = d['priceVip'];
                    completeMovieData['roomName'] = d['roomName'];
                    completeMovieData['roomFormat'] = d['roomFormat'];
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
    final docs = _realShowtimes!;
    final dates = docs.map((d) => (d.data() as Map)['date'] as String).toSet().toList()..sort();
    final timesForDate = docs
        .where((d) => (d.data() as Map)['date'] == _selectedDate)
        .toList()
      ..sort((a, b) => ((a.data() as Map)['time'] as String).compareTo((b.data() as Map)['time'] as String));

    return [
      const Text('2. CHỌN NGÀY XEM PHIM', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
      const SizedBox(height: 12),
      SizedBox(
        height: 45,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: dates.length,
          itemBuilder: (context, index) {
            final date = dates[index];
            final isSelected = _selectedDate == date;
            return GestureDetector(
              onTap: () => setState(() {
                _selectedDate = date;
                _selectedTime = null;
                _selectedShowtimeDoc = null;
              }),
              child: Container(
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.amber : const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(date, style: TextStyle(color: isSelected ? Colors.black : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 25),
      const Text('3. CHỌN KHUNG GIỜ CHIẾU', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
      const SizedBox(height: 12),
      if (_selectedDate == null)
        const Text('Chọn ngày để xem khung giờ.', style: TextStyle(color: Colors.white38, fontSize: 12))
      else
        // Cùng 1 khung giờ có thể có nhiều suất chiếu riêng biệt (khác phòng/
        // định dạng: 2D Phụ đề, 2D Lồng tiếng, VIP, Premium) - so sánh theo
        // doc.id thay vì chuỗi giờ để không gộp nhầm 2 suất trùng giờ khác phòng.
        GridView.builder(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.7),
          itemCount: timesForDate.length,
          itemBuilder: (context, index) {
            final doc = timesForDate[index];
            final data = doc.data() as Map;
            final time = data['time'] as String;
            final format = data['roomFormat'] as String? ?? '2D Phụ đề';
            final isSelected = _selectedShowtimeDoc?.id == doc.id;
            final formatColor = roomFormatColor(format);
            return GestureDetector(
              onTap: () => setState(() {
                _selectedTime = time;
                _selectedShowtimeDoc = doc;
              }),
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.amber : const Color(0xFF0A0A0A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.05)),
                ),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 3),
                    Text(format,
                        style: TextStyle(color: isSelected ? Colors.black54 : formatColor, fontWeight: FontWeight.bold, fontSize: 8)),
                  ],
                ),
              ),
            );
          },
        ),
    ];
  }
}