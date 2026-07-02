import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/user_provider.dart';
import '../../../providers/theaters_provider.dart';
import 'admin_audit_log.dart';

class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  String _search = '';

  @override
  Widget build(BuildContext context) {
    final theaterNames = ref.watch(theaterNamesProvider);
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'QUẢN LÝ NGƯỜI DÙNG',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          // ── Search bar ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Tìm theo email hoặc tên...',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
                filled: true,
                fillColor: const Color(0xFF1E1E2A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (v) => setState(() => _search = v.toLowerCase()),
            ),
          ),

          // ── User list ────────────────────────────────────────────────────────
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('users').snapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.amber));
                }
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return const Center(
                    child: Text('Chưa có người dùng nào.', style: TextStyle(color: Colors.white38)),
                  );
                }

                final docs = snap.data!.docs.where((doc) {
                  final d = doc.data() as Map<String, dynamic>;
                  final email = (d['email'] ?? '').toLowerCase();
                  final name = (d['displayName'] ?? '').toLowerCase();
                  return _search.isEmpty || email.contains(_search) || name.contains(_search);
                }).toList();

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, i) => _UserCard(doc: docs[i], theaterNames: theaterNames),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ── User card ────────────────────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  final QueryDocumentSnapshot doc;
  final List<String> theaterNames;
  const _UserCard({required this.doc, required this.theaterNames});

  UserRole _parseRole(Map<String, dynamic> data) {
    return UserRoleExt.fromString(
      data['role'] as String?,
      legacyIsAdmin: data['isAdmin'] == true,
    );
  }

  Color _roleColor(UserRole role) {
    switch (role) {
      case UserRole.admin: return Colors.amber;
      case UserRole.theaterManager: return Colors.deepPurpleAccent;
      case UserRole.staff: return Colors.tealAccent;
      case UserRole.user: return Colors.lightBlueAccent;
    }
  }

  IconData _roleIcon(UserRole role) {
    switch (role) {
      case UserRole.admin: return Icons.admin_panel_settings_rounded;
      case UserRole.theaterManager: return Icons.business_rounded;
      case UserRole.staff: return Icons.badge_rounded;
      case UserRole.user: return Icons.person_rounded;
    }
  }

  void _showRoleDialog(BuildContext context, Map<String, dynamic> data, UserRole currentRole) {
    UserRole selected = currentRole;
    String? selectedTheater = data['assignedTheater'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          backgroundColor: const Color(0xFF16161F),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'PHÂN QUYỀN NGƯỜI DÙNG',
            style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                data['email'] ?? '',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text('Chọn vai trò:', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 8),
              ...UserRole.values.map((role) => RadioListTile<UserRole>(
                value: role,
                groupValue: selected,
                activeColor: _roleColor(role),
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Row(
                  children: [
                    Icon(_roleIcon(role), color: _roleColor(role), size: 16),
                    const SizedBox(width: 8),
                    Text(role.label, style: TextStyle(color: _roleColor(role), fontSize: 13)),
                  ],
                ),
                onChanged: (v) => setDlg(() => selected = v!),
              )),
              if (selected == UserRole.staff || selected == UserRole.theaterManager) ...[
                const SizedBox(height: 12),
                const Text('Rạp phụ trách:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedTheater,
                  dropdownColor: const Color(0xFF1E1E2A),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1E1E2A),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  hint: const Text('Chọn rạp', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  items: theaterNames.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => setDlg(() => selectedTheater = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('HỦY', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                final updates = <String, dynamic>{
                  'role': selected.firestoreValue,
                  'isAdmin': selected == UserRole.admin,
                  if (selectedTheater != null) 'assignedTheater': selectedTheater,
                  if (selected == UserRole.user || selected == UserRole.admin)
                    'assignedTheater': FieldValue.delete(),
                };
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(doc.id)
                    .update(updates);
                await logAdminAction(
                  action: 'change_role',
                  targetCollection: 'users',
                  targetId: doc.id,
                  before: {'role': data['role'], 'assignedTheater': data['assignedTheater']},
                  after: {'role': selected.firestoreValue, 'assignedTheater': selectedTheater},
                );
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.amber),
              child: const Text('LƯU', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = doc.data() as Map<String, dynamic>;
    final email = data['email'] ?? '—';
    final displayName = data['displayName'] ?? '';
    final phone = data['phone'] ?? '';
    final wallet = (data['wallet_balance'] as num? ?? 0).toInt();
    final role = _parseRole(data);
    final assignedTheater = data['assignedTheater'] as String?;
    final color = _roleColor(role);
    final initials = displayName.isNotEmpty
        ? displayName.substring(0, displayName.length >= 2 ? 2 : 1).toUpperCase()
        : email.substring(0, 2).toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16161F),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.12)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withOpacity(0.15),
            child: Text(initials, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        displayName.isNotEmpty ? displayName : email,
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: color.withOpacity(0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_roleIcon(role), color: color, size: 10),
                          const SizedBox(width: 3),
                          Text(role.label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (displayName.isNotEmpty)
                  Text(email, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                if (phone.isNotEmpty)
                  Text(phone, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                if (assignedTheater != null)
                  Text(assignedTheater, style: const TextStyle(color: Colors.tealAccent, fontSize: 10)),
                const SizedBox(height: 2),
                Text(
                  'Ví: ${_fmt(wallet)} đ',
                  style: const TextStyle(color: Colors.amber, fontSize: 11),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white38, size: 20),
            color: const Color(0xFF1E1E2A),
            onSelected: (value) {
              if (value == 'role') _showRoleDialog(context, data, role);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'role',
                child: Row(
                  children: [
                    Icon(Icons.manage_accounts_rounded, color: Colors.amber, size: 18),
                    SizedBox(width: 8),
                    Text('Phân quyền', style: TextStyle(color: Colors.white, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(int v) =>
      v.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
}
