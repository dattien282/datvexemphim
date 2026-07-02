import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final ticketRepositoryProvider = Provider<TicketRepository>((ref) {
  return TicketRepository();
});

class TicketRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<QueryDocumentSnapshot>> getUserTicketsStream(String userId) {
    return _firestore
        .collection('tickets')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs);
  }
}
