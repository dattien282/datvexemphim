import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'admin_movies_screen.dart';
import 'admin_users_screen.dart';
import 'admin_vouchers_screen.dart';
import 'admin_revenue_screen.dart';

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  static Future<bool> isAdmin(String uid) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null) return false;
    return data['isAdmin'] == true || data['role'] == 'admin';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F13),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'ADMIN DASHBOARD',
          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Stats row ──────────────────────────────────────────────────
            _SectionTitle(title: 'TỔNG QUAN'),
            const SizedBox(height: 12),
            const _StatsRow(),
            const SizedBox(height: 24),

            // ── Revenue chart ──────────────────────────────────────────────
            _SectionTitle(title: 'DOANH THU GẦN ĐÂY'),
            const SizedBox(height: 12),
            const _RevenueCard(),
            const SizedBox(height: 24),

            // ── Quick actions ──────────────────────────────────────────────
            _SectionTitle(title: 'QUẢN LÝ'),
            const SizedBox(height: 12),
            _buildActionGrid(context),
            const SizedBox(height: 24),

            // ── Recent tickets ─────────────────────────────────────────────
            _SectionTitle(title: 'VÉ MỚI NHẤT'),
            const SizedBox(height: 12),
            const _RecentTickets(),
          ],
        ),
      ),
    );
  }

  Widget _buildActionGrid(BuildContext context) {
    final actions = [
      _AdminAction(Icons.movie_creation_rounded, 'Quản lý\nPhim', Colors.blue,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminMoviesScreen()))),
      _AdminAction(Icons.people_alt_rounded, 'Quản lý\nNgười dùng', Colors.purple,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsersScreen()))),
      _AdminAction(Icons.local_offer_rounded, 'Voucher\n& Khuyến mãi', Colors.orange,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminVouchersScreen()))),
      _AdminAction(Icons.bar_chart_rounded, 'Báo cáo\nDoanh thu', Colors.green,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminRevenueScreen()))),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.6,
      children: actions.map((a) => _buildActionCard(a)).toList(),
    );
  }

  Widget _buildActionCard(_AdminAction action) {
    return GestureDetector(
      onTap: action.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: action.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: action.color.withValues(alpha: 0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(action.icon, color: action.color, size: 28),
            const SizedBox(height: 8),
            Text(
              action.label,
              textAlign: TextAlign.center,
              style: TextStyle(color: action.color, fontSize: 12, fontWeight: FontWeight.bold, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminAction {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AdminAction(this.icon, this.label, this.color, this.onTap);
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 16, decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
      ],
    );
  }
}

// ── Stats row (Firestore aggregate) ─────────────────────────────────────────
class _StatsRow extends StatelessWidget {
  const _StatsRow();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('tickets').snapshots(),
      builder: (context, ticketSnap) {
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance.collection('users').snapshots(),
          builder: (context, userSnap) {
            return StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('movies').snapshots(),
              builder: (context, movieSnap) {
                final totalTickets = ticketSnap.data?.docs.length ?? 0;
                final totalUsers = userSnap.data?.docs.length ?? 0;
                final totalMovies = movieSnap.data?.docs.length ?? 0;

                return Row(
                  children: [
                    _statCard('Tổng vé', '$totalTickets', Icons.confirmation_number_rounded, Colors.amber),
                    const SizedBox(width: 10),
                    _statCard('Người dùng', '$totalUsers', Icons.people_rounded, Colors.blue),
                    const SizedBox(width: 10),
                    _statCard('Phim', '$totalMovies', Icons.movie_rounded, Colors.purple),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

Widget _statCard(String label, String value, IconData icon, Color color) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(value, style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      ),
    ),
  );
}

// ── Revenue card ─────────────────────────────────────────────────────────────
class _RevenueCard extends StatelessWidget {
  const _RevenueCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tickets')
          .where('payment_status', isEqualTo: 'COMPLETED')
          .snapshots(),
      builder: (context, snap) {
        int cancelledCount = 0;
        int completedCount = 0;
        int totalRevenue = 0;

        if (snap.hasData) {
          completedCount = snap.data!.docs.length;
          for (final doc in snap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            // Sửa lỗi sai tên field: totalPrice đồng bộ với RecentTickets
            totalRevenue += (data['totalPrice'] as num? ?? 0).toInt();
          }
        }

        final formatted = totalRevenue.toString()
            .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A2A1A), Color(0xFF0F1F0F)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.green.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('TỔNG DOANH THU', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              const SizedBox(height: 8),
              Text('$formatted đ', style: const TextStyle(color: Colors.greenAccent, fontSize: 28, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Row(
                children: [
                  _revenueStat(Icons.check_circle_rounded, 'Giao dịch thành công', '$completedCount', Colors.green),
                  const SizedBox(width: 20),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('tickets')
                        .where('payment_status', isEqualTo: 'CANCELLED')
                        .snapshots(),
                    builder: (context, cancelSnap) {
                      cancelledCount = cancelSnap.data?.docs.length ?? 0;
                      return _revenueStat(Icons.cancel_rounded, 'Đã hủy', '$cancelledCount', Colors.redAccent);
                    },
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

Widget _revenueStat(IconData icon, String label, String value, Color color) {
  return Row(
    children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 6),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold)),
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      ),
    ],
  );
}

// ── Recent tickets ────────────────────────────────────────────────────────────
class _RecentTickets extends StatelessWidget {
  const _RecentTickets();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('tickets')
          .orderBy('created_at', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(child: Text('Chưa có vé nào.', style: TextStyle(color: Colors.white38)));
        }

        return Column(
          children: snap.data!.docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final status = d['payment_status'] ?? 'UNKNOWN';
            final statusColor = status == 'COMPLETED'
                ? Colors.greenAccent
                : status == 'CANCELLED'
                    ? Colors.redAccent
                    : Colors.amber;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF16161F),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.confirmation_number_rounded, color: Colors.amber, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d['movieTitle'] ?? d['title'] ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(d['email'] ?? d['userId'] ?? '—', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${((d['totalPrice'] as num? ?? 0).toInt()).toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ',
                        style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          status == 'COMPLETED' ? 'Thành công' : status == 'CANCELLED' ? 'Đã hủy' : status,
                          style: TextStyle(color: statusColor, fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}
