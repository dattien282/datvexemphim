import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../booking_and_payment/screens/showtime_selection_screen.dart';

class PromoPopup extends StatefulWidget {
  final Map<String, dynamic> movieData;
  const PromoPopup({super.key, required this.movieData});

  @override
  State<PromoPopup> createState() => _PromoPopupState();
}

class _PromoPopupState extends State<PromoPopup> {
  bool _dontShowAgain = false;

  Future<void> _close() async {
    if (_dontShowAgain) {
      final title = widget.movieData['title'] as String? ?? '';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('promo_dismissed_$title', true);
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.movieData['title'] as String? ?? 'Phim đang chiếu';
    final genre = widget.movieData['genre'] as String? ?? '';
    final posterUrl = widget.movieData['posterUrl'] as String? ?? '';
    final rating = widget.movieData['rating']?.toString();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: posterUrl.isEmpty
                        ? Container(color: const Color(0xFF1E1E2A), child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 60))
                        : CachedNetworkImage(
                            imageUrl: posterUrl,
                            fit: BoxFit.cover,
                            placeholder: (_, _) => Container(color: const Color(0xFF1E1E2A)),
                            errorWidget: (_, _, _) => Container(color: const Color(0xFF1E1E2A), child: const Icon(Icons.movie_rounded, color: Colors.white24, size: 60)),
                          ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    onTap: _close,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                      child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(6)),
                    child: const Text('ĐANG CHIẾU', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (rating != null) ...[
                        const Icon(Icons.star_rounded, color: Colors.amber, size: 14),
                        const SizedBox(width: 2),
                        Text(rating, style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(genre, style: const TextStyle(color: Colors.white54, fontSize: 12), overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Checkbox(
                    value: _dontShowAgain,
                    onChanged: (v) => setState(() => _dontShowAgain = v ?? false),
                    activeColor: Colors.amber,
                    side: const BorderSide(color: Colors.white38),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _dontShowAgain = !_dontShowAgain),
                      child: const Text('Không hiển thị lại thông báo này', style: TextStyle(color: Colors.white38, fontSize: 11)),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _close,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('Để sau', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () async {
                        final navigator = Navigator.of(context);
                        if (_dontShowAgain) {
                          final title2 = widget.movieData['title'] as String? ?? '';
                          final prefs = await SharedPreferences.getInstance();
                          await prefs.setBool('promo_dismissed_$title2', true);
                        }
                        if (!mounted) return;
                        navigator.pop(); // đóng pop-up
                        navigator.push(
                          MaterialPageRoute(builder: (_) => ShowtimeSelectionScreen(movieData: widget.movieData)),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('MUA NGAY', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
