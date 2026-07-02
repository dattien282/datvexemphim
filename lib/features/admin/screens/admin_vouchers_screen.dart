import 'package:flutter/material.dart';
import 'voucher_widgets.dart';

class AdminVouchersScreen extends StatelessWidget {
  const AdminVouchersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF16161F),
        elevation: 0,
        centerTitle: true,
        title: const Text('VOUCHER & KHUYẾN MÃI',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 15)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded, color: Colors.orange),
            onPressed: () => VoucherDialog.show(context),
            tooltip: 'Thêm voucher',
          ),
        ],
      ),
      body: const VoucherListView(),
    );
  }
}
