import 'package:flutter/material.dart';
import '../../admin/screens/voucher_widgets.dart';

/// Voucher tab scoped to the manager's own theater. Vouchers created here
/// always get theaterScope == theater, so they never leak into other
/// theaters' checkout and admin can still see them (theaterScope != null)
/// alongside global vouchers in AdminVouchersScreen.
class TheaterVoucherTab extends StatelessWidget {
  final String theater;
  const TheaterVoucherTab({super.key, required this.theater});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orange,
        onPressed: () => VoucherDialog.show(context, lockedTheaterScope: theater),
        child: const Icon(Icons.add_rounded, color: Colors.black),
      ),
      body: VoucherListView(theaterScopeFilter: theater),
    );
  }
}
