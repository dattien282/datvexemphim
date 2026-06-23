import 'package:flutter/material.dart';
import 'seat_booking_screen.dart';

class ShowtimeSelectionScreen extends StatefulWidget {
  final Map<String, dynamic> movieData;
  const ShowtimeSelectionScreen({super.key, required this.movieData});

  @override
  State<ShowtimeSelectionScreen> createState() => _ShowtimeSelectionScreenState();
}

class _ShowtimeSelectionScreenState extends State<ShowtimeSelectionScreen> {
  String? _selectedTheater;
  String? _selectedDate;
  String? _selectedTime;

  // DANH SÁCH HỆ THỐNG ĐẠI RẠP STELLA ĐỊNH VỊ THỰC TẾ
  final List<String> _theaters = [
    'Stella Cinema Nguyễn Du (Quận 1)',
    'Stella Cinema Vạn Hạnh Mall (Quận 10)',
    'Stella Cinema Mipec Long Biên (Hà Nội)',
    'Stella Cinema Đà Nẵng (Thanh Khê)',
    'Stella Cinema Cần Thơ (Sense City)'
  ];

  // HỆ THỐNG NGÀY CHIẾU LỊCH TRÌNH THỰC TẾ DYNAMIC THEO THỜI GIAN THỰC
  final List<String> _dates = [];

  // KHUNG SUẤT CHIẾU ĐỘNG CHUYÊN NGHIỆP
  final List<String> _showtimes = ['09:30', '12:15', '15:00', '17:45', '19:30', '21:15', '23:00'];

  @override
  void initState() {
    super.initState();
    _generateRealTimeDates();
  }

  void _generateRealTimeDates() {
    final now = DateTime.now();
    for (int i = 0; i < 4; i++) {
      final date = now.add(Duration(days: i));
      String prefix = "";
      if (i == 0) {
        prefix = "Hôm nay";
      } else {
        switch (date.weekday) {
          case DateTime.monday:
            prefix = "Thứ Hai";
            break;
          case DateTime.tuesday:
            prefix = "Thứ Ba";
            break;
          case DateTime.wednesday:
            prefix = "Thứ Tư";
            break;
          case DateTime.thursday:
            prefix = "Thứ Năm";
            break;
          case DateTime.friday:
            prefix = "Thứ Sáu";
            break;
          case DateTime.saturday:
            prefix = "Thứ Bảy";
            break;
          case DateTime.sunday:
            prefix = "Chủ Nhật";
            break;
        }
      }
      final dayStr = date.day.toString().padLeft(2, '0');
      final monthStr = date.month.toString().padLeft(2, '0');
      _dates.add("$prefix ($dayStr/$monthStr)");
    }
    // Chọn sẵn ngày hôm nay mặc định
    if (_dates.isNotEmpty) {
      _selectedDate = _dates[0];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
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
              dropdownColor: const Color(0xFF16161F),
              decoration: InputDecoration(
                filled: true, fillColor: const Color(0xFF16161F),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              hint: const Text('Vui lòng chọn cụm rạp gần bạn', style: TextStyle(color: Colors.white38, fontSize: 13)),
              value: _selectedTheater,
              items: _theaters.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (val) => setState(() => _selectedTheater = val),
            ),
            const SizedBox(height: 25),

            // 2. CHỌN NGÀY CHIẾU (Dạng thẻ trượt ngang mượt mà)
            const Text('2. CHỌN NGÀY XEM PHIM', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 12),
            SizedBox(
              height: 45,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _dates.length,
                itemBuilder: (context, index) {
                  final date = _dates[index];
                  final isSelected = _selectedDate == date;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedDate = date),
                    child: Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.amber : const Color(0xFF16161F),
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

            // 3. CHỌN SUẤT CHIẾU GIỜ GIẤC
            const Text('3. CHỌN KHUNG GIỜ CHIẾU', style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 2.2),
              itemCount: _showtimes.length,
              itemBuilder: (context, index) {
                final time = _showtimes[index];
                final isSelected = _selectedTime == time;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTime = time),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.amber : const Color(0xFF16161F),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.05)),
                    ),
                    alignment: Alignment.center,
                    child: Text(time, style: TextStyle(color: isSelected ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                );
              },
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
}