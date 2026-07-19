import 'package:flutter/material.dart';
import 'voucher_widgets.dart';

class AdminVouchersScreen extends StatelessWidget {
  const AdminVouchersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF09090F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F14),
        elevation: 0,
        centerTitle: true,
        title: const Text(
          'VOUCHER & ƯU ĐÃI',
          style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: const Icon(Icons.add_rounded, color: Colors.amber),
              onPressed: () => VoucherDialog.show(context),
              tooltip: 'Thêm voucher',
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: Colors.white.withValues(alpha: 0.05),
            height: 1,
          ),
        ),
      ),
      body: const VoucherListView(),
    );
  }
}
