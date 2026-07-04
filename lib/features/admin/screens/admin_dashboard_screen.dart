import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../main.dart';
import 'admin_movies_screen.dart';
import 'admin_users_screen.dart';
import 'admin_vouchers_screen.dart';
import 'admin_revenue_screen.dart';
import 'admin_reviews_screen.dart';
import 'admin_broadcast_screen.dart';
import 'admin_audit_log_screen.dart';
import 'admin_age_verification_screen.dart';
import 'admin_server_config_screen.dart';
import '../../../providers/user_provider.dart';

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
    final userProfile = ref.watch(userProfileProvider).value;
    
    return Scaffold(
      backgroundColor: const Color(0xFF111115),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'ADMIN DASHBOARD',
          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1),
        ),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.redAccent),
            onPressed: () => _handleAdminLogout(context),
            tooltip: 'Đăng xuất',
          ),
        ],
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
            _buildActionGrid(context, userProfile),
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

  Widget _buildActionGrid(BuildContext context, UserProfile? userProfile) {
    final role = userProfile?.role ?? UserRole.admin;

    final actions = <_AdminAction>[];

    // Quyền Admin: thấy tất cả
    // Quyền Kế toán: thấy Doanh thu
    // Quyền Marketing: thấy Khuyến mãi, Thông báo
    if (role == UserRole.admin) {
      actions.add(_AdminAction(Icons.movie_creation_rounded, 'Quản lý\nPhim', Colors.blue,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminMoviesScreen()))));
      actions.add(_AdminAction(Icons.people_alt_rounded, 'Quản lý\nNgười dùng', Colors.purple,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminUsersScreen()))));
      actions.add(_AdminAction(Icons.local_offer_rounded, 'Voucher\n& Khuyến mãi', Colors.orange,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminVouchersScreen()))));
      actions.add(_AdminAction(Icons.bar_chart_rounded, 'Báo cáo\nDoanh thu', Colors.green,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminRevenueScreen()))));
      actions.add(_AdminAction(Icons.rate_review_rounded, 'Kiểm duyệt\nĐánh giá', Colors.pinkAccent,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminReviewsScreen()))));
      actions.add(_AdminAction(Icons.campaign_rounded, 'Gửi thông báo\nchung', Colors.amber,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminBroadcastScreen()))));
      actions.add(_AdminAction(Icons.history_rounded, 'Nhật ký\nHành động', Colors.cyanAccent,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAuditLogScreen()))));
      actions.add(_AdminAction(Icons.badge_rounded, 'Duyệt xác minh\nđộ tuổi', Colors.redAccent,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminAgeVerificationScreen()))));
      actions.add(_AdminAction(Icons.settings_suggest_rounded, 'Cấu hình\nServer', Colors.blueGrey,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminServerConfigScreen()))));
    } else if (role == UserRole.accountant) {
      actions.add(_AdminAction(Icons.bar_chart_rounded, 'Báo cáo\nDoanh thu', Colors.green,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminRevenueScreen()))));
    } else if (role == UserRole.marketing) {
      actions.add(_AdminAction(Icons.local_offer_rounded, 'Voucher\n& Khuyến mãi', Colors.orange,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminVouchersScreen()))));
      actions.add(_AdminAction(Icons.campaign_rounded, 'Gửi thông báo\nchung', Colors.amber,
          () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminBroadcastScreen()))));
    }

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
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            action.color.withValues(alpha: 0.2),
            action.color.withValues(alpha: 0.05)
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: action.color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: action.color.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: action.onTap,
          splashColor: action.color.withValues(alpha: 0.2),
          highlightColor: action.color.withValues(alpha: 0.1),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: action.color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(action.icon, color: action.color, size: 28),
              ),
              const SizedBox(height: 12),
              Text(
                action.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9), 
                  fontSize: 12, 
                  fontWeight: FontWeight.bold, 
                  height: 1.3
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _handleAdminLogout(BuildContext context) async {
  final navigator = Navigator.of(context);
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF0A0A0A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('ĐĂNG XUẤT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
      content: const Text('Bạn có chắc muốn đăng xuất?', style: TextStyle(color: Colors.white70, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('KHÔNG', style: TextStyle(color: Colors.grey))),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('ĐĂNG XUẤT', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
  if (confirm == true) {
    await FirebaseAuth.instance.signOut();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const MainAppWrapper()),
      (route) => false,
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
                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance.collection('showtimes').snapshots(),
                  builder: (context, showtimeSnap) {
                    final totalOrders = ticketSnap.data?.docs.length ?? 0;
                    final totalUsers = userSnap.data?.docs.length ?? 0;
                    final totalMovies = movieSnap.data?.docs.length ?? 0;
                    
                    // Tính tổng ghế đã bán
                    int totalSeatsSold = 0;
                    if (ticketSnap.data != null) {
                      for (final doc in ticketSnap.data!.docs) {
                        final data = doc.data() as Map<String, dynamic>;
                        final seats = data['seats'] as List<dynamic>? ?? [];
                        totalSeatsSold += seats.length;
                      }
                    }

                    // Ước tính công suất (104 ghế / 1 suất chiếu xấp xỉ)
                    final totalShowtimes = showtimeSnap.data?.docs.length ?? 0;
                    final totalCapacity = totalShowtimes * 104;
                    final double occupancyRate = totalCapacity > 0 ? (totalSeatsSold / totalCapacity * 100) : 0.0;

                    return Column(
                      children: [
                        Row(
                          children: [
                            _statCard('Lấp đầy', '${occupancyRate.toStringAsFixed(1)}%', Icons.pie_chart_rounded, Colors.greenAccent),
                            const SizedBox(width: 10),
                            _statCard('Tổng đơn', '$totalOrders', Icons.confirmation_number_rounded, Colors.amber),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _statCard('Người dùng', '$totalUsers', Icons.people_rounded, Colors.blue),
                            const SizedBox(width: 10),
                            _statCard('Phim', '$totalMovies', Icons.movie_rounded, Colors.purple),
                          ],
                        ),
                      ],
                    );
                  }
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0.2),
            color.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 12),
          Text(value, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w500)),
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
          .where('paymentStatus', whereIn: ['COMPLETED', 'CHECKED_IN'])
          .snapshots(),
      builder: (context, snap) {
        int cancelledCount = 0;
        int completedCount = 0;
        int totalRevenue = 0;

        if (snap.hasData) {
          completedCount = snap.data!.docs.length;
          for (final doc in snap.data!.docs) {
            final data = doc.data() as Map<String, dynamic>;
            totalRevenue += (data['totalAmount'] as num? ?? 0).toInt();
          }
        }

        final formatted = totalRevenue.toString()
            .replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2E7D32), Color(0xFF1B5E20)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.greenAccent.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.account_balance_wallet_rounded, color: Colors.white70, size: 16),
                  SizedBox(width: 8),
                  Text('TỔNG DOANH THU TOÀN HỆ THỐNG', style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
                ],
              ),
              const SizedBox(height: 12),
              Text('$formatted đ', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
              const SizedBox(height: 20),
              Container(height: 1, color: Colors.white.withValues(alpha: 0.1)),
              const SizedBox(height: 20),
              Row(
                children: [
                  _revenueStat(Icons.check_circle_rounded, 'Giao dịch thành công', '$completedCount', Colors.lightGreenAccent),
                  const SizedBox(width: 20),
                  StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('tickets')
                        .where('paymentStatus', isEqualTo: 'CANCELLED')
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
          .orderBy('createdAt', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(child: Text('Chưa có vé nào.', style: TextStyle(color: Colors.white38)));
        }

        return Column(
          children: snap.data!.docs.map((doc) {
            final d = doc.data() as Map<String, dynamic>;
            final status = d['paymentStatus'] ?? 'UNKNOWN';
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
                        Text(d['movieTitle'] ?? '—', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(d['email'] ?? d['userId'] ?? '—', style: const TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${((d['totalAmount'] as num? ?? 0).toInt()).toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.')} đ',
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
