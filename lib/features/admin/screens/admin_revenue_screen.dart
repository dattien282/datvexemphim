import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as xls;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../../../providers/theaters_provider.dart';

class AdminRevenueScreen extends ConsumerStatefulWidget {
  const AdminRevenueScreen({super.key});

  @override
  ConsumerState<AdminRevenueScreen> createState() => _AdminRevenueScreenState();
}

class _AdminRevenueScreenState extends ConsumerState<AdminRevenueScreen> {
  DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  DateTime _to = DateTime.now();
  String? _theaterFilter;

  @override
  Widget build(BuildContext context) {
    final theaterNames = ref.watch(theaterNamesProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
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
              border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                  isExpanded: true,
                  initialValue: _theaterFilter,
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
                    ...theaterNames.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
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
        .where('paymentStatus', whereIn: ['COMPLETED', 'CHECKED_IN'])
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(to.add(const Duration(days: 1))));

    if (theater != null) {
      query = query.where('theaterName', isEqualTo: theater);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: query.orderBy('createdAt', descending: true).snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.green));
        }
        final docs = snap.data?.docs ?? [];
        final revenue = docs.fold<int>(0, (s, d) => s + ((d.data() as Map)['totalAmount'] as num? ?? 0).toInt());
        final tickets = docs.length;
        final avgOrder = tickets > 0 ? revenue ~/ tickets : 0;

        // Count by movie
        final Map<String, int> byMovie = {};
        // Count by theater (chỉ có ý nghĩa khi không lọc theo 1 rạp cụ thể)
        final Map<String, int> byTheater = {};
        // Count by Combo
        final Map<String, int> byCombo = {};
        
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          final title = data['movieTitle'] ?? '—';
          byMovie[title] = (byMovie[title] ?? 0) + ((data['totalAmount'] as num?)?.toInt() ?? 0);
          final theaterName = data['theaterName'] ?? '—';
          byTheater[theaterName] = (byTheater[theaterName] ?? 0) + ((data['totalAmount'] as num?)?.toInt() ?? 0);

          // Parse combos
          final combosList = data['combos'] as List<dynamic>?;
          if (combosList != null) {
            for (final c in combosList) {
              if (c is Map<String, dynamic>) {
                final cTitle = c['title'] ?? 'Unknown';
                final qty = (c['quantity'] as num?)?.toInt() ?? 0;
                byCombo[cTitle] = (byCombo[cTitle] ?? 0) + qty;
              }
            }
          }
        }
        final topMovies = byMovie.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topTheaters = byTheater.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topCombos = byCombo.entries.toList()
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: docs.isEmpty
                          ? null
                          : () => _exportPdf(context, revenue: revenue, tickets: tickets, avgOrder: avgOrder, topMovies: topMovies, topTheaters: topTheaters, docs: docs),
                      icon: const Icon(Icons.picture_as_pdf_rounded, color: Colors.redAccent, size: 16),
                      label: const Text('Xuất PDF', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.redAccent)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: docs.isEmpty
                          ? null
                          : () => _exportExcel(context, revenue: revenue, tickets: tickets, avgOrder: avgOrder, topMovies: topMovies, topTheaters: topTheaters, docs: docs),
                      icon: const Icon(Icons.grid_on_rounded, color: Colors.greenAccent, size: 16),
                      label: const Text('Xuất Excel', style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.greenAccent)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Revenue by theater (ẩn khi đã lọc theo 1 rạp cụ thể - vô nghĩa)
              if (theater == null && topTheaters.length > 1) ...[
                _sectionTitle('DOANH THU THEO RẠP'),
                const SizedBox(height: 10),
                ...topTheaters.map((entry) {
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
                              child: Row(
                                children: [
                                  const Icon(Icons.location_city_rounded, color: Colors.blueAccent, size: 14),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(entry.key,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
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
                            valueColor: const AlwaysStoppedAnimation(Colors.blueAccent),
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

              // Top Combos
              _sectionTitle('TOP BẮP NƯỚC BÁN CHẠY'),
              const SizedBox(height: 10),
              if (topCombos.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(bottom: 20),
                  child: Text('Chưa có dữ liệu bắp nước', style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
              ...topCombos.take(5).map((entry) {
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161F),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.pinkAccent.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.fastfood_rounded, color: Colors.pinkAccent, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(entry.key, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      ),
                      Text('${entry.value} phần', style: const TextStyle(color: Colors.pinkAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 20),

              // Recent transactions
              _sectionTitle('GIAO DỊCH GẦN ĐÂY'),
              const SizedBox(height: 10),
              ...docs.take(10).map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                DateTime? ts;
                if (d['createdAt'] != null) {
                  ts = (d['createdAt'] as Timestamp).toDate();
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
                            Text(d['movieTitle'] ?? '—',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            Text(d['email'] ?? '—', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                            if (ts != null)
                              Text(DateFormat('dd/MM/yyyy HH:mm').format(ts),
                                  style: const TextStyle(color: Colors.white24, fontSize: 9)),
                          ],
                        ),
                      ),
                      Text('${_fmt((d['totalAmount'] as num? ?? 0).toInt())} đ',
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
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
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

  String get _rangeLabel =>
      '${DateFormat('dd/MM/yyyy').format(from)} - ${DateFormat('dd/MM/yyyy').format(to)}${theater != null ? ' • $theater' : ''}';

  Future<void> _exportPdf(
    BuildContext context, {
    required int revenue,
    required int tickets,
    required int avgOrder,
    required List<MapEntry<String, int>> topMovies,
    required List<MapEntry<String, int>> topTheaters,
    required List<QueryDocumentSnapshot> docs,
  }) async {
    try {
      final doc = pw.Document();
      doc.addPage(
        pw.MultiPage(
          build: (ctx) => [
            pw.Header(level: 0, text: 'BAO CAO DOANH THU - STELLA CINEMA'),
            pw.Text('Khoang thoi gian: $_rangeLabel'),
            pw.SizedBox(height: 12),
            pw.Text('Tong doanh thu: ${_fmt(revenue)} d', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            pw.Text('Ve ban duoc: $tickets'),
            pw.Text('Trung binh/don: ${_fmt(avgOrder)} d'),
            pw.SizedBox(height: 16),
            if (topTheaters.length > 1) ...[
              pw.Header(level: 1, text: 'Doanh thu theo rap'),
              pw.TableHelper.fromTextArray(
                headers: ['Rap', 'Doanh thu (d)'],
                data: topTheaters.map((e) => [e.key, _fmt(e.value)]).toList(),
              ),
              pw.SizedBox(height: 16),
            ],
            pw.Header(level: 1, text: 'Phim doanh thu cao nhat'),
            pw.TableHelper.fromTextArray(
              headers: ['Phim', 'Doanh thu (d)'],
              data: topMovies.take(10).map((e) => [e.key, _fmt(e.value)]).toList(),
            ),
            pw.SizedBox(height: 16),
            pw.Header(level: 1, text: 'Giao dich (${docs.length})'),
            pw.TableHelper.fromTextArray(
              headers: ['Phim', 'Email', 'Ngay', 'So tien (d)'],
              data: docs.map((d) {
                final data = d.data() as Map<String, dynamic>;
                final ts = data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : null;
                return [
                  data['movieTitle'] ?? '-',
                  data['email'] ?? '-',
                  ts != null ? DateFormat('dd/MM/yyyy HH:mm').format(ts) : '-',
                  _fmt((data['totalAmount'] as num? ?? 0).toInt()),
                ];
              }).toList(),
            ),
          ],
        ),
      );
      await Printing.sharePdf(bytes: await doc.save(), filename: 'bao_cao_doanh_thu.pdf');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xuất PDF: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _exportExcel(
    BuildContext context, {
    required int revenue,
    required int tickets,
    required int avgOrder,
    required List<MapEntry<String, int>> topMovies,
    required List<MapEntry<String, int>> topTheaters,
    required List<QueryDocumentSnapshot> docs,
  }) async {
    try {
      final wb = xls.Excel.createExcel();
      final defaultSheetName = wb.getDefaultSheet();
      final sheet = wb['Doanh thu'];
      if (defaultSheetName != null && defaultSheetName != 'Doanh thu') {
        wb.delete(defaultSheetName);
      }

      void addRow(List<dynamic> cells) {
        sheet.appendRow(cells.map((c) => xls.TextCellValue(c.toString())).toList());
      }

      addRow(['BÁO CÁO DOANH THU - STELLA CINEMA']);
      addRow(['Khoảng thời gian', _rangeLabel]);
      addRow(['Tổng doanh thu (đ)', _fmt(revenue)]);
      addRow(['Vé bán được', tickets]);
      addRow(['Trung bình/đơn (đ)', _fmt(avgOrder)]);
      addRow([]);

      if (topTheaters.length > 1) {
        addRow(['DOANH THU THEO RẠP']);
        addRow(['Rạp', 'Doanh thu (đ)']);
        for (final e in topTheaters) {
          addRow([e.key, e.value]);
        }
        addRow([]);
      }

      addRow(['PHIM DOANH THU CAO NHẤT']);
      addRow(['Phim', 'Doanh thu (đ)']);
      for (final e in topMovies) {
        addRow([e.key, e.value]);
      }
      addRow([]);

      addRow(['GIAO DỊCH']);
      addRow(['Phim', 'Email', 'Ngày', 'Số tiền (đ)']);
      for (final d in docs) {
        final data = d.data() as Map<String, dynamic>;
        final ts = data['createdAt'] != null ? (data['createdAt'] as Timestamp).toDate() : null;
        addRow([
          data['movieTitle'] ?? '—',
          data['email'] ?? '—',
          ts != null ? DateFormat('dd/MM/yyyy HH:mm').format(ts) : '—',
          (data['totalAmount'] as num? ?? 0).toInt(),
        ]);
      }

      final bytes = wb.encode();
      if (bytes == null) throw Exception('Không tạo được file Excel');

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/bao_cao_doanh_thu.xlsx');
      await file.writeAsBytes(bytes);
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: 'Báo cáo doanh thu Stella Cinema'),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xuất Excel: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }
}
