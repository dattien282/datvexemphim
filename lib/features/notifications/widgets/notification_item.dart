import 'package:flutter/material.dart';

class NotificationItem extends StatelessWidget {
  final String title;
  final String message;
  final String time;
  final bool isRead;
  final VoidCallback onTap;

  const NotificationItem({
    Key? key,
    required this.title,
    required this.message,
    required this.time,
    required this.isRead,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isRead ? Colors.transparent : Colors.blue.withOpacity(0.05),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon trạng thái
            CircleAvatar(
              radius: 24,
              backgroundColor: isRead ? Colors.grey[200] : Colors.blue[100],
              child: Icon(
                Icons.local_activity,
                color: isRead ? Colors.grey : Colors.blue,
              ),
            ),
            const SizedBox(width: 16),
            // Nội dung thông báo
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: TextStyle(color: Colors.grey[700]),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    time,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
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