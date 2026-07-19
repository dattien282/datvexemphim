import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

enum BannerAction { movie, combo, profile, voucher }

class BannerItem {
  final String imageUrl;
  final String badge;
  final Color badgeColor;
  final String title;
  final String subtitle;
  final BannerAction action;
  final String? movieTitle; // dùng khi action == movie
  final String? voucherCode; // dùng khi action == voucher

  const BannerItem({
    required this.imageUrl,
    required this.badge,
    required this.badgeColor,
    required this.title,
    required this.subtitle,
    required this.action,
    this.movieTitle,
    this.voucherCode,
  });
}

class BannerCarousel extends StatefulWidget {
  final List<BannerItem> items;
  final void Function(BannerItem) onTap;
  const BannerCarousel({super.key, required this.items, required this.onTap});

  @override
  State<BannerCarousel> createState() => _BannerCarouselState();
}

class _BannerCarouselState extends State<BannerCarousel> {
  final PageController _ctrl = PageController();
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _autoScroll();
  }

  void _autoScroll() {
    Future.delayed(const Duration(seconds: 4), () {
      if (!mounted) return;
      _index = (_index + 1) % widget.items.length;
      if (_ctrl.hasClients) {
        _ctrl.animateToPage(_index,
            duration: const Duration(milliseconds: 800), curve: Curves.fastOutSlowIn);
      }
      _autoScroll();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 200,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: PageView.builder(
              controller: _ctrl,
              itemCount: widget.items.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (_, index) {
                final item = widget.items[index];
                return GestureDetector(
                  onTap: () => widget.onTap(item),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: item.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, _) => Container(color: const Color(0xFF222232)),
                        errorWidget: (_, _, _) => Container(
                          color: const Color(0xFF222232),
                          child: const Icon(Icons.movie_creation_rounded, color: Colors.white30, size: 48),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.3),
                              Colors.black.withValues(alpha: 0.85),
                            ],
                            stops: const [0.3, 0.6, 1.0],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 16, right: 16, bottom: 16,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: item.badgeColor, borderRadius: BorderRadius.circular(6)),
                              child: Text(item.badge,
                                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                            ),
                            const SizedBox(height: 6),
                            Text(item.title,
                                style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 0.5,
                                    shadows: [Shadow(color: Colors.black54, blurRadius: 4)])),
                            const SizedBox(height: 4),
                            Text(item.subtitle,
                                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, height: 1.3),
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Positioned(
            right: 12, bottom: 12,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(widget.items.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.only(left: 4),
                  width: active ? 16 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? Colors.amber : Colors.white38,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}
