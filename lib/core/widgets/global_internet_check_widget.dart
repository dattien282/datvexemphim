import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';

class GlobalInternetCheckWidget extends StatefulWidget {
  const GlobalInternetCheckWidget({super.key});

  @override
  State<GlobalInternetCheckWidget> createState() => _GlobalInternetCheckWidgetState();
}

class _GlobalInternetCheckWidgetState extends State<GlobalInternetCheckWidget> {
  bool _hasInternet = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _checkConnection();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkConnection());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com').timeout(const Duration(seconds: 3));
      final connected = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      if (mounted && _hasInternet != connected) {
        setState(() {
          _hasInternet = connected;
        });
      }
    } catch (_) {
      if (mounted && _hasInternet) {
        setState(() {
          _hasInternet = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasInternet) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(10),
            boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: const Material(
            color: Colors.transparent,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text(
                  'Mất kết nối Internet! Đang kiểm tra lại...',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
