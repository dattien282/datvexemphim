import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminAuditLogScreen extends StatefulWidget {
  const AdminAuditLogScreen({super.key});

  @override
  State<AdminAuditLogScreen> createState() => _AdminAuditLogScreenState();
}

class _AdminAuditLogScreenState extends State<AdminAuditLogScreen> {
  String _selectedFilter = 'all'; // all, create, update, delete, broadcast, other
  final Map<String, String> _filters = const {
    'all': 'Tất cả',
    'create': 'Tạo mới',
    'update': 'Cập nhật',
    'delete': 'Xóa',
    'broadcast': 'Thông báo',
    'other': 'Khác',
  };

  Color _getActionColor(String action) {
    action = action.toLowerCase();
    if (action.contains('delete')) return Colors.redAccent;
    if (action.contains('create')) return Colors.greenAccent;
    if (action.contains('update')) return Colors.orangeAccent;
    if (action.contains('broadcast')) return Colors.purpleAccent;
    return Colors.cyanAccent;
  }

  bool _matchesFilter(String action) {
    action = action.toLowerCase();
    if (_selectedFilter == 'all') return true;
    if (_selectedFilter == 'create') return action.contains('create') || action.contains('add');
    if (_selectedFilter == 'update') return action.contains('update') || action.contains('edit');
    if (_selectedFilter == 'delete') return action.contains('delete') || action.contains('remove');
    if (_selectedFilter == 'broadcast') return action.contains('broadcast') || action.contains('send');
    if (_selectedFilter == 'other') {
      return !action.contains('create') &&
          !action.contains('add') &&
          !action.contains('update') &&
          !action.contains('edit') &&
          !action.contains('delete') &&
          !action.contains('remove') &&
          !action.contains('broadcast') &&
          !action.contains('send');
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('NHẬT KÝ HÀNH ĐỘNG',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // Filter Chips Row
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: _filters.entries.map((entry) {
                final isSelected = _selectedFilter == entry.key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      entry.value,
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedFilter = entry.key);
                      }
                    },
                    selectedColor: Colors.amber,
                    backgroundColor: const Color(0xFF16161F),
                    checkmarkColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide.none),
                  ),
                );
              }).toList(),
            ),
          ),
          
          // Log List
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('admin_audit_log')
                  .orderBy('timestamp', descending: true)
                  .limit(150)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.amber));
                }
                if (snap.hasError) {
                  return Center(child: Text('Lỗi tải nhật ký: ${snap.error}', style: const TextStyle(color: Colors.redAccent)));
                }
                final allDocs = snap.data?.docs ?? [];
                final docs = allDocs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final action = d['action'] ?? '';
                  return _matchesFilter(action);
                }).toList();

                if (docs.isEmpty) {
                  return const Center(child: Text('Không tìm thấy nhật ký phù hợp.', style: TextStyle(color: Colors.white38)));
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final d = docs[i].data() as Map<String, dynamic>;
                    final ts = (d['timestamp'] as Timestamp?)?.toDate();
                    final action = d['action'] ?? '—';
                    final color = _getActionColor(action);
                    
                    return _AuditLogTile(
                      action: action,
                      color: color,
                      adminEmail: d['adminEmail'] ?? '—',
                      targetCollection: d['targetCollection'] ?? '—',
                      targetId: d['targetId'] ?? '—',
                      timestamp: ts,
                      details: d['after'] ?? d['before'] ?? {},
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AuditLogTile extends StatefulWidget {
  final String action;
  final Color color;
  final String adminEmail;
  final String targetCollection;
  final String targetId;
  final DateTime? timestamp;
  final Map<String, dynamic> details;

  const _AuditLogTile({
    required this.action,
    required this.color,
    required this.adminEmail,
    required this.targetCollection,
    required this.targetId,
    this.timestamp,
    required this.details,
  });

  @override
  State<_AuditLogTile> createState() => _AuditLogTileState();
}

class _AuditLogTileState extends State<_AuditLogTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ts = widget.timestamp;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: widget.color.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        widget.action.toUpperCase(),
                        style: TextStyle(color: widget.color, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ),
                    const Spacer(),
                    if (ts != null)
                      Text(
                        '${ts.day.toString().padLeft(2, '0')}/${ts.month.toString().padLeft(2, '0')}/${ts.year} ${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.white38, fontSize: 10),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.person_outline_rounded, color: Colors.amber, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.adminEmail,
                        style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.folder_open_rounded, color: Colors.white38, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${widget.targetCollection} • ID: ${widget.targetId}',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.details.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _expanded = !_expanded),
                        child: Icon(
                          _expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                          color: Colors.amber,
                          size: 20,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          
          if (_expanded && widget.details.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF1E1E2A),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CHI TIẾT THAY ĐỔI:',
                    style: TextStyle(color: Colors.amber, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 6),
                  ...widget.details.entries.map((entry) {
                    final key = entry.key;
                    final val = entry.value;
                    if (val is Map || val is List) return const SizedBox.shrink(); // Ẩn nested phức tạp để tránh rối UI
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$key: ',
                            style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: Text(
                              '$val',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
