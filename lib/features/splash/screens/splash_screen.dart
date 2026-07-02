import 'package:flutter/material.dart';

/// Màn hình chờ hiển thị ảnh thương hiệu Stella Cinema (assets/images/login.png)
/// trong ~2 giây khi mở app, sau đó tự mờ dần (fade) sang màn hình chào
/// (MainAppWrapper). [next] được truyền vào từ main.dart để tránh import
/// vòng (splash không cần biết chi tiết MainAppWrapper).
class SplashScreen extends StatefulWidget {
  final Widget next;
  const SplashScreen({super.key, required this.next});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  double _opacity = 0;

  @override
  void initState() {
    super.initState();
    // Fade-in ảnh ngay khi vào app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _opacity = 1);
    });
    // Sau 2.2s, chuyển sang màn chào với hiệu ứng fade mượt.
    Future.delayed(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (context, animation, secondaryAnimation) => widget.next,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: AnimatedOpacity(
        opacity: _opacity,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeIn,
        child: Image.asset(
          'assets/images/login.png',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
        ),
      ),
    );
  }
}
