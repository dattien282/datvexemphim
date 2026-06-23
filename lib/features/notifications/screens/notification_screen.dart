import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _markAsRead(String docId) {
    FirebaseFirestore.instance.collection('user_notifications').doc(docId).update({'isRead': true});
  }

  void _clearAllNotifications() async {
    final snapshots = await FirebaseFirestore.instance.collection('user_notifications').get();
    for (var doc in snapshots.docs) {
      await doc.reference.delete();
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Đã xóa toàn bộ thông báo thành công.')),
    );
  }

  String _formatNotificationTime(dynamic createdAtField, String? fallbackTime) {
    if (createdAtField == null) {
      return fallbackTime ?? 'Vừa xong';
    }

    DateTime dateTime;
    if (createdAtField is Timestamp) {
      dateTime = createdAtField.toDate();
    } else if (createdAtField is DateTime) {
      dateTime = createdAtField;
    } else {
      return fallbackTime ?? 'Vừa xong';
    }

    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.isNegative) {
      return DateFormat('HH:mm - dd/MM/yyyy').format(dateTime);
    }

    if (difference.inSeconds < 60) {
      return 'Vừa xong';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} phút trước';
    } else if (difference.inHours < 24) {
      if (dateTime.day == now.day && dateTime.month == now.month && dateTime.year == now.year) {
        return 'Hôm nay lúc ${DateFormat('HH:mm').format(dateTime)}';
      } else {
        return 'Hôm qua lúc ${DateFormat('HH:mm').format(dateTime)}';
      }
    } else if (difference.inDays < 2) {
      final yesterday = now.subtract(const Duration(days: 1));
      if (dateTime.day == yesterday.day && dateTime.month == yesterday.month && dateTime.year == yesterday.year) {
        return 'Hôm qua lúc ${DateFormat('HH:mm').format(dateTime)}';
      }
    }

    return DateFormat('HH:mm - dd/MM/yyyy').format(dateTime);
  }

  Widget _getNotiIcon(String type) {
    switch (type) {
      case 'ticket':
        return const Icon(Icons.confirmation_number_rounded, color: Colors.amber, size: 20);
      case 'promo':
        return const Icon(Icons.card_giftcard_rounded, color: Colors.lightGreenAccent, size: 20);
      default:
        return const Icon(Icons.notifications_active_rounded, color: Colors.cyanAccent, size: 20);
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
        title: const Text(
          'TRUNG TÂM THÔNG BÁO',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _clearAllNotifications,
            child: const Text('Xóa tất cả', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.amber,
          indicatorWeight: 3,
          labelColor: Colors.amber,
          unselectedLabelColor: Colors.grey,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          tabs: const [
            Tab(text: 'Tất cả'),
            Tab(text: 'Giao dịch'),
            Tab(text: 'Hệ thống'),
          ],
          onTap: (index) => setState(() {}),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // Sắp xếp real-time theo thời gian tạo mới nhất lên đầu
        stream: FirebaseFirestore.instance.collection('user_notifications').orderBy('created_at', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Colors.amber));
          }

          List<QueryDocumentSnapshot> docs = snapshot.hasData ? snapshot.data!.docs : [];

          return TabBarView(
            controller: _tabController,
            children: [
              _buildNotiList(docs, 0), // Tab Tất cả
              _buildNotiList(docs, 1), // Tab Giao dịch
              _buildNotiList(docs, 2), // Tab Hệ thống
            ],
          );
        },
      ),
    );
  }

  Widget _buildNotiList(List<QueryDocumentSnapshot> allDocs, int tabIndex) {
    List<QueryDocumentSnapshot> filteredDocs = [];

    // Phân loại logic Tab
    if (tabIndex == 0) {
      filteredDocs = allDocs;
    } else if (tabIndex == 1) {
      filteredDocs = allDocs.where((d) {
        final data = d.data() as Map<String, dynamic>;
        return data['type'] == 'ticket';
      }).toList();
    } else {
      filteredDocs = allDocs.where((d) {
        final data = d.data() as Map<String, dynamic>;
        return data['type'] != 'ticket';
      }).toList();
    }

    if (filteredDocs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_rounded, color: Colors.white24, size: 54),
            SizedBox(height: 12),
            Text('Hộp thư thông báo trống.', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredDocs.length,
      itemBuilder: (context, index) {
        final doc = filteredDocs[index];
        final noti = doc.data() as Map<String, dynamic>;
        final bool isRead = noti['isRead'] ?? false;
        final String type = noti['type'] ?? 'system';

        return TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 150 + (index * 60)),
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(20 * (1 - value), 0),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: Dismissible(
            key: Key(doc.id),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.only(right: 20),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.centerRight,
              child: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent, size: 24),
            ),
            onDismissed: (direction) {
              FirebaseFirestore.instance.collection('user_notifications').doc(doc.id).delete();
            },
            child: GestureDetector(
              onTap: () => _markAsRead(doc.id),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isRead ? const Color(0xFF16161F) : const Color(0xFF1E1E2A),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isRead ? Colors.white.withValues(alpha: 0.03) : Colors.amber.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.04), shape: BoxShape.circle),
                      child: Center(child: _getNotiIcon(type)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  noti['title'] ?? 'Thông báo hệ thống',
                                  style: TextStyle(
                                    color: isRead ? Colors.white70 : Colors.white,
                                    fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (!isRead)
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                                ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            noti['content'] ?? '',
                            style: const TextStyle(color: Colors.grey, fontSize: 12, height: 1.4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _formatNotificationTime(noti['created_at'], noti['time']),
                            style: const TextStyle(color: Colors.white38, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}