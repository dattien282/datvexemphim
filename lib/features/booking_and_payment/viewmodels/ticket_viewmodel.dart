import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/ticket_repository.dart';

final userTicketsProvider = StreamProvider.autoDispose<List<QueryDocumentSnapshot>>((ref) {
  final repository = ref.watch(ticketRepositoryProvider);
  final user = FirebaseAuth.instance.currentUser;
  
  if (user == null) {
    return const Stream.empty();
  }
  
  return repository.getUserTicketsStream(user.uid);
});
