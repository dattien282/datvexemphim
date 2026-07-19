import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

class TheaterAttendanceScreen extends StatefulWidget {
  final String theater;
  const TheaterAttendanceScreen({super.key, required this.theater});

  @override
  State<TheaterAttendanceScreen> createState() => _TheaterAttendanceScreenState();
}

class _TheaterAttendanceScreenState extends State<TheaterAttendanceScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final qrData = jsonEncode({
      'type': 'attendance',
      'theater': widget.theater,
      'date': todayStr,
    });

    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: Column(
          children: [
            const Text('ĐIỂM DANH CA LÀM',
                style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
            Text(widget.theater, style: const TextStyle(color: Colors.white38, fontSize: 10)),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.amber,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.white38,
          tabs: const [
            Tab(text: 'MÃ ĐIỂM DANH'),
            Tab(text: 'LỊCH SỬ HÔM NAY'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          // QR CODE VIEW
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                const Text(
                  'Yêu cầu nhân viên dùng app quét mã QR này để điểm danh vào ca (Check-in) hoặc ra ca (Check-out).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.withValues(alpha: 0.2),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: QrImageView(
                    data: qrData,
                    version: QrVersions.auto,
                    size: 240.0,
                    eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
                    dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                  ),
                ),
                const SizedBox(height: 30),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.date_range_rounded, color: Colors.amber, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Ngày: ${DateFormat('dd/MM/yyyy').format(DateTime.now())}',
                        style: const TextStyle(color: Colors.amber, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // ATTENDANCE LOG VIEW
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('attendance_logs')
                .where('theater', isEqualTo: widget.theater)
                .where('date', isEqualTo: todayStr)
                .orderBy('checkInTime', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator(color: Colors.amber));
              }
              if (snap.hasError) {
                return Center(
                  child: Text('Lỗi tải nhật ký: ${snap.error}', style: const TextStyle(color: Colors.redAccent)),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return const Center(
                  child: Text('Hôm nay chưa có nhân viên nào điểm danh.',
                      style: TextStyle(color: Colors.white38, fontSize: 13)),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: docs.length,
                itemBuilder: (ctx, i) {
                  final d = docs[i].data() as Map<String, dynamic>;
                  final name = d['displayName'] ?? d['email'] ?? 'Unknown';
                  final email = d['email'] ?? '';
                  final checkInVal = d['checkInTime'] as Timestamp?;
                  final checkOutVal = d['checkOutTime'] as Timestamp?;
                  final status = d['status'] as String? ?? 'check_in';
                  
                  final inTimeStr = checkInVal != null 
                      ? DateFormat('HH:mm:ss').format(checkInVal.toDate()) 
                      : '—';
                  final outTimeStr = checkOutVal != null 
                      ? DateFormat('HH:mm:ss').format(checkOutVal.toDate()) 
                      : 'Chưa về';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16161F),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: (status == 'check_out' ? Colors.blue : Colors.green).withValues(alpha: 0.15),
                          child: Icon(
                            status == 'check_out' ? Icons.logout_rounded : Icons.login_rounded,
                            color: status == 'check_out' ? Colors.blueAccent : Colors.greenAccent,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(email, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.arrow_forward_rounded, color: Colors.greenAccent, size: 12),
                                  const SizedBox(width: 4),
                                  Text('Vào: $inTimeStr', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                  const SizedBox(width: 16),
                                  const Icon(Icons.arrow_back_rounded, color: Colors.blueAccent, size: 12),
                                  const SizedBox(width: 4),
                                  Text('Ra: $outTimeStr', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: (status == 'check_out' ? Colors.blue : Colors.green).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status == 'check_out' ? 'RA CA' : 'VÀO CA',
                            style: TextStyle(
                              color: status == 'check_out' ? Colors.blueAccent : Colors.greenAccent,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
