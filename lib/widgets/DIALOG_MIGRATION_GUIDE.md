# Dialog Migration Guide

## Overview
All dialogs, alerts, and popups have been unified into `AppDialog`, `AppToast`, and `AppBottomSheet`.

## Quick Reference

### Before (Old)
```dart
showDialog(
  context: context,
  builder: (_) => AlertDialog(
    title: Text('Logout?'),
    content: Text('You will need to login again.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
      ElevatedButton(onPressed: () { /* ... */ }, child: Text('Logout')),
    ],
  ),
);
```

### After (New)
```dart
AppDialog.confirm(
  context,
  title: 'Logout?',
  message: 'You will need to login again.',
  confirmLabel: 'Logout',
  onConfirm: () { /* ... */ },
);
```

---

## API Reference

### 1. Confirmation Dialogs
```dart
AppDialog.confirm(
  context,
  title: 'Confirm Action',
  message: 'Are you sure?',
  confirmLabel: 'Yes',
  cancelLabel: 'No',
  onConfirm: () { /* action */ },
  onCancel: () { /* optional */ },
);
```

### 2. Destructive Actions
```dart
AppDialog.destructive(
  context,
  title: 'Delete Position?',
  message: 'This action cannot be undone.',
  confirmLabel: 'Delete',
  onConfirm: () { /* delete */ },
);
```

### 3. Success Messages
```dart
AppDialog.success(
  context,
  title: 'Order Placed',
  message: 'Your order was submitted successfully.',
  closeLabel: 'Done',
);
```

### 4. Error Messages
```dart
AppDialog.error(
  context,
  title: 'Order Failed',
  message: 'Insufficient balance for this trade.',
  closeLabel: 'OK',
);
```

### 5. Warnings
```dart
AppDialog.warning(
  context,
  title: 'Trading Halted',
  message: 'Market is currently closed.',
  confirmLabel: 'Got it',
  onConfirm: () { /* ... */ },
);
```

### 6. Info Dialogs
```dart
AppDialog.info(
  context,
  title: 'Feature Coming Soon',
  message: 'This feature will be available in the next update.',
  closeLabel: 'OK',
);
```

### 7. Input Dialogs
```dart
AppDialog.input(
  context,
  title: 'New Watchlist',
  message: 'Enter a name for your watchlist',
  hint: 'Watchlist name',
  confirmLabel: 'Create',
  onSubmit: (value) { /* use value */ },
  validator: (v) => v?.isEmpty == true ? 'Name required' : null,
);
```

### 8. Custom Body
```dart
AppDialog.confirm(
  context,
  title: 'Exit Position',
  message: 'Available: 100 qty',
  body: TextField(
    controller: qtyController,
    decoration: InputDecoration(labelText: 'Quantity to exit'),
  ),
  confirmLabel: 'Exit',
  onConfirm: () { /* ... */ },
);
```

---

## Toast Messages (SnackBar Replacement)

### Before
```dart
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text('Order placed'),
    backgroundColor: AppColors.success,
  ),
);
```

### After
```dart
AppToast.success(context, 'Order placed');
AppToast.error(context, 'Order failed');
AppToast.warning(context, 'Market closed');
AppToast.info(context, 'Feature coming soon');
```

---

## Bottom Sheets

### Before
```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => Container(
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    child: /* content */,
  ),
);
```

### After
```dart
AppBottomSheet.show(
  context,
  title: 'Edit Profile',
  child: Column(
    children: [
      TextField(/* ... */),
      ElevatedButton(/* ... */),
    ],
  ),
);
```

---

## Migration Checklist

### High Priority (User-facing)
- [x] Logout confirmation (profile_screen.dart)
- [x] Position exit dialogs (positions_screen.dart)
- [x] Order placement toasts (order_form_drawer.dart)
- [x] IPO application (ipo_screen.dart)
- [x] Withdrawal confirmation (withdraw_funds_screen.dart)

### Medium Priority (Admin)
- [ ] Force close position (force_close_positions_screen.dart)
- [ ] Trading halt toggle (risk_control_screen.dart)
- [ ] User balance adjustment (admin_users_screen.dart)

### Low Priority (Settings/Features)
- [ ] Watchlist management (market_watch_screen.dart)
- [ ] GTT order form (gtt_orders_screen.dart)
- [ ] Basket orders (basket_orders_screen.dart)
- [ ] Chart compare (advanced_chart_screen.dart)
- [ ] Alert creation (alert_creation_screen.dart)

---

## Design Principles

1. **Consistent Spacing**: 24px padding, 16px between elements
2. **Corner Radius**: 22px for dialogs, 12px for toasts
3. **Icon Size**: 52px circle badge, 24px icon inside
4. **Typography**: Inter 17px/w700 title, 14px/w400 message
5. **Button Height**: 52px touch target
6. **Animations**: 220ms ease-out-cubic scale + fade
7. **Colors**: Type-specific (blue confirm, red destructive, green success)
8. **Dark Mode**: Automatic adaptation via Theme.of(context).brightness

---

## Benefits

✅ **Consistent UX** — Same look/feel everywhere  
✅ **Less Code** — 3 lines vs 20 lines  
✅ **Type Safety** — Enum-driven types  
✅ **Dark Mode** — Automatic support  
✅ **Animations** — Smooth scale + fade  
✅ **Accessibility** — Proper touch targets  
✅ **Premium Feel** — iOS-inspired design  
✅ **Maintainable** — Single source of truth  

---

## Examples from Codebase

### Logout (profile_screen.dart)
```dart
// OLD
showDialog(
  context: context,
  builder: (_) => AlertDialog(
    title: const Text('Logout?'),
    content: const Text('You will need to login again to continue trading.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      ElevatedButton(
        onPressed: () { /* logout */ },
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
        child: const Text('Logout'),
      ),
    ],
  ),
);

// NEW
AppDialog.destructive(
  context,
  title: 'Logout?',
  message: 'You will need to login again to continue trading.',
  confirmLabel: 'Logout',
  onConfirm: () { /* logout */ },
);
```

### Square Off All (positions_screen.dart)
```dart
// OLD
showDialog(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('Square Off All'),
    content: const Text('Close all open positions at market price?'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ElevatedButton(
        onPressed: () { /* square off */ },
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
        child: const Text('Square Off All'),
      ),
    ],
  ),
);

// NEW
AppDialog.destructive(
  context,
  title: 'Square Off All',
  message: 'Close all open positions at market price?',
  confirmLabel: 'Square Off All',
  onConfirm: () { /* square off */ },
);
```

### Order Success (order_form_drawer.dart)
```dart
// OLD
ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Row(
      children: [
        const Icon(LucideIcons.checkCircle, color: Colors.white, size: 16),
        const SizedBox(width: 8),
        const Expanded(child: Text('Order submitted successfully')),
      ],
    ),
    backgroundColor: AppColors.success,
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
);

// NEW
AppToast.success(context, 'Order submitted successfully');
```

### New Watchlist (market_watch_screen.dart)
```dart
// OLD
final controller = TextEditingController();
final name = await showDialog<String>(
  context: context,
  builder: (ctx) => AlertDialog(
    title: const Text('New Watchlist'),
    content: TextField(
      controller: controller,
      autofocus: true,
      decoration: const InputDecoration(hintText: 'Watchlist name'),
    ),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
      ElevatedButton(
        onPressed: () => Navigator.pop(ctx, controller.text.trim()),
        child: const Text('Create'),
      ),
    ],
  ),
);

// NEW
AppDialog.input(
  context,
  title: 'New Watchlist',
  hint: 'Watchlist name',
  confirmLabel: 'Create',
  onSubmit: (name) { /* use name */ },
);
```
