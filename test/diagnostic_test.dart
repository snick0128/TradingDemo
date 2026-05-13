import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:box_trading_web/firebase_options.dart';

void main() {
  test('Diagnostic: Check User Data', () async {
    WidgetsFlutterBinding.ensureInitialized();
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: 'Snick0128@gmail.com')
          .get();

      if (snap.docs.isEmpty) {
        print('USER_CHECK: NOT_FOUND');
      } else {
        final data = snap.docs.first.data();
        print('USER_CHECK: FOUND');
        print('DATA: $data');
        print('BALANCE_TYPE: ${data['balance']?.runtimeType}');
        print(
          'AVAILABLE_BALANCE_TYPE: ${data['available_balance']?.runtimeType}',
        );
      }
    } catch (e) {
      print('USER_CHECK: ERROR $e');
    }
  });
}
