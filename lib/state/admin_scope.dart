import 'package:flutter/material.dart';
import 'admin_store.dart';

class AdminScope extends InheritedNotifier<AdminStore> {
  const AdminScope({
    super.key,
    required AdminStore super.notifier,
    required super.child,
  });

  static AdminStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AdminScope>();
    assert(scope != null, 'No AdminScope found in context');
    return scope!.notifier!;
  }
}
