import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class AdminRevenueScreen extends StatefulWidget {
  const AdminRevenueScreen({super.key});

  @override
  State<AdminRevenueScreen> createState() => _AdminRevenueScreenState();
}

class _AdminRevenueScreenState extends State<AdminRevenueScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  String? _theaterFilter;

  static const _theaters = [
    'Stella Cinema – Hồ Chí Minh',
    'Stella Cinema – Hà Nội',
    'Stella Cinema – Đà Nẵng',
    'Stella Cinema – Cần Thơ',
    'Stella Cinema – Hải Phòng',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('BÁO CÁO DOANH THU',
            style: TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // ── Filter panel ──────────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF16161F),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('BỘ LỌC',
                    style: TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _datePicker('Từ ngày', _from, (d) => setState(() => _from = d))),
                    const SizedBox(width: 12),
                    Expanded(child: _datePicker('Đến ngày', _to, (d) => setState(() => _to = d))),
                  ],
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String?>(
                  value: _theaterFilter,
                  dropdownColor: const Color(0xFF1E1E2A),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E1E2A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    prefixIcon: const Icon(Icons.location_city_rounded, color: Colors.green, size: 18),
                  ),
                  hint: const Text('Tất cả rạp', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Tất cả rạp', style: TextStyle(color: Colors.white54))),
                    ..._theaters.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                  ],
                  onChanged: (v) => setState(() => _theaterFilter = v),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => setState(() {
                        _from = DateTime.now().subtract(const Duration(days: 30));
                        _to = DateTime.now();
                        _theaterFilter = null;
                      }),
                      child: const Text('Đặt lại', style: TextStyle(color: Colors.white38)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Report content ────────────────────────────────────────────────
          Expanded(
            child: _ReportBody(from: _from, to: _to, theater: _theaterFilter),
          ),
        ],
      ),
    );
  }

  Widget _datePicker(String label, DateTime value, void Function(DateTime) onPick) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2020),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          builder: (ctx, child) => Theme(
            data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: Colors.green)),
            child: child!,
          ),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E2A),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_rounded, color: Colors.green, size: 14),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white38, fontSize: 9)),
                Text(DateFormat('dd/MM/yyyy').format(value),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Report body ───────────────────────────────────────────────────────────────
class _ReportBody extends StatelessWidget {
  final DateTime from;
  final DateTime to;
  final String? theater;
  const _ReportBody({required this.from, required this.to, this.theater});

  @override
  Widget build(BuildContext context) {
    Query query = FirebaseFirestore.instance
        .collection('tickets')
        .where('payment_status', isEqualTo: 'COMPLETED')
        .where('created_at', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('created_at', isLessThanOrEqualTo: Timestamp.fromDate(to.add(const Duration(days: 1))));

    if (theater != null) {
      query = query.where('theater', isEqualTo: theater);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.orderBy('created_at', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.green));
        }
        final docs = snap.data?.docs ?? [];
        final revenue = docs.fold<int>(0, (s, d) => s + ((d.data() as Map)['totalPrice'] as num? ?? 0).toInt());
        final tickets = docs.length;
        final avgOrder = tickets > 0 ? revenue ~/ tickets : 0;

        // Count by movie
        final Map<String, int> byMovie = {};
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          final title = data['title'] ?? '—';
          byMovie[title] = (byMovie[title] ?? 0) + ((data['totalPrice'] as num?)?.toInt() ?? 0);
        }
        final topMovies = byMovie.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: Column(
            children: [
              // Summary cards
              Row(
                children: [
                  Expanded(child: _card('Tổng doanh thu', '${_fmt(revenue)} đ', Icons.monetization_on_rounded, Colors.green)),
                  const SizedBox(width: 10),
                  Expanded(child: _card('Vé bán được', '$tickets', Icons.confirmation_number_rounded, Colors.amber)),
                ],
              ),
              const SizedBox(height: 10),
              _card('Trung bình/đơn', '${_fmt(avgOrder)} đ', Icons.analytics_rounded, Colors.blue),
              const SizedBox(height: 20),

              // Top movies by revenue
              if (topMovies.isNotEmpty) ...[
                _sectionTitle('PHIM DOANH THU CAO NHẤT'),
                const SizedBox(height: 10),
                ...topMovies.take(5).map((entry) {
                  final pct = revenue > 0 ? entry.value / revenue : 0.0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161F),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(entry.key,
                                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            Text('${_fmt(entry.value)} đ',
                                style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: pct,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation(Colors.green),
                            minHeight: 6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text('${(pct * 100).toStringAsFixed(1)}% tổng doanh thu',
                            style: const TextStyle(color: Colors.white38, fontSize: 10)),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 20),
              ],

              // Recent transactions
              _sectionTitle('GIAO DỊCH GẦN ĐÂY'),
              const SizedBox(height: 10),
              ...docs.take(10).map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                DateTime? ts;
                if (d['created_at'] != null) {
                  ts = (d['created_at'] as Timestamp).toDate();
                }
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161F),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded, color: Colors.white24, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d['title'] ?? '—',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            Text(d['email'] ?? '—', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            if (ts != null)
                              Text(DateFormat('dd/MM/yyyy HH:mm').format(ts),
                                  style: const TextStyle(color: Colors.white24, fontSize: 9)),
                          ],
                        ),
                      ),
                      Text('${_fmt((d['totalPrice'] as num? ?? 0).toInt())} đ',
                          style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Widget _card(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold)),
                Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Row(
      children: [
        Container(width: 3, height: 14, decoration: BoxDecoration(color: Colors.green, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(t, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
      ],
    );
  }

  static String _fmt(int v) =>
      v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}
