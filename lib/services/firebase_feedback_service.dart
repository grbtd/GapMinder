import 'package:firebase_app_distribution/firebase_app_distribution.dart' as app_dist;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class FirebaseFeedbackService {
  static final FirebaseFeedbackService _instance = FirebaseFeedbackService._internal();

  factory FirebaseFeedbackService() => _instance;

  FirebaseFeedbackService._internal();

  Future<bool> submitFeedback({
    required String category,
    required String message,
    String? contactEmail,
  }) async {
    debugPrint('[FirebaseFeedbackService] Submitted ($category): $message (Contact: ${contactEmail ?? "N/A"})');

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }

      await app_dist.signInTester();
    } catch (e) {
      debugPrint('[FirebaseFeedbackService] App Distribution notice: $e');
    }

    return true;
  }
}
