import 'package:flutter/widgets.dart';

import 'security_store.dart';

class SecurityScope extends InheritedNotifier<SecurityStore> {
  const SecurityScope({
    super.key,
    required SecurityStore super.notifier,
    required super.child,
  });

  static SecurityStore of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<SecurityScope>();
    assert(scope != null, 'SecurityScope is not available in this context.');
    return scope!.notifier!;
  }
}
