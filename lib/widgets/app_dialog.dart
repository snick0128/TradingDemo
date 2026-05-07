/// AppDialog — Unified premium popup/dialog/sheet system
///
/// Usage:
///   AppDialog.confirm(context, title: '...', message: '...', onConfirm: () {})
///   AppDialog.destructive(context, title: '...', message: '...', onConfirm: () {})
///   AppDialog.success(context, title: '...', message: '...')
///   AppDialog.error(context, title: '...', message: '...')
///   AppDialog.warning(context, title: '...', message: '...')
///   AppDialog.info(context, title: '...', message: '...')
///   AppDialog.input(context, title: '...', onSubmit: (v) {})
///   AppDialog.show(context, config: AppDialogConfig(...))
///   AppToast.success(context, '...')
///   AppToast.error(context, '...')
///   AppToast.info(context, '...')

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme.dart';
import 'global_toast.dart';

// ─── Dialog Type ──────────────────────────────────────────────────────────────

enum AppDialogType { confirm, destructive, success, error, warning, info, input }

// ─── Dialog Config ────────────────────────────────────────────────────────────

class AppDialogConfig {
  final AppDialogType type;
  final String title;
  final String? message;
  final Widget? body;           // custom content below message
  final String? confirmLabel;
  final String? cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool barrierDismissible;

  const AppDialogConfig({
    required this.type,
    required this.title,
    this.message,
    this.body,
    this.confirmLabel,
    this.cancelLabel,
    this.onConfirm,
    this.onCancel,
    this.barrierDismissible = true,
  });
}

// ─── Main API ─────────────────────────────────────────────────────────────────

class AppDialog {
  AppDialog._();

  /// Generic show — full control via config
  static Future<void> show(BuildContext context, {required AppDialogConfig config}) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: config.barrierDismissible,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) => _AppDialogWidget(config: config),
    );
  }

  /// Confirmation dialog (blue primary button)
  static Future<void> confirm(
    BuildContext context, {
    required String title,
    String? message,
    Widget? body,
    String confirmLabel = 'Confirm',
    String cancelLabel = 'Cancel',
    required VoidCallback onConfirm,
    VoidCallback? onCancel,
  }) {
    return show(context, config: AppDialogConfig(
      type: AppDialogType.confirm,
      title: title,
      message: message,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      onConfirm: onConfirm,
      onCancel: onCancel,
    ));
  }

  /// Destructive action dialog (red confirm button)
  static Future<void> destructive(
    BuildContext context, {
    required String title,
    String? message,
    Widget? body,
    String confirmLabel = 'Delete',
    String cancelLabel = 'Cancel',
    required VoidCallback onConfirm,
    VoidCallback? onCancel,
  }) {
    return show(context, config: AppDialogConfig(
      type: AppDialogType.destructive,
      title: title,
      message: message,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      onConfirm: onConfirm,
      onCancel: onCancel,
    ));
  }

  /// Success dialog (green icon, single close button)
  static Future<void> success(
    BuildContext context, {
    required String title,
    String? message,
    Widget? body,
    String closeLabel = 'Done',
    VoidCallback? onClose,
  }) {
    return show(context, config: AppDialogConfig(
      type: AppDialogType.success,
      title: title,
      message: message,
      body: body,
      confirmLabel: closeLabel,
      onConfirm: onClose,
    ));
  }

  /// Error dialog (red icon, single close button)
  static Future<void> error(
    BuildContext context, {
    required String title,
    String? message,
    Widget? body,
    String closeLabel = 'OK',
    VoidCallback? onClose,
  }) {
    return show(context, config: AppDialogConfig(
      type: AppDialogType.error,
      title: title,
      message: message,
      body: body,
      confirmLabel: closeLabel,
      onConfirm: onClose,
    ));
  }

  /// Warning dialog (orange icon)
  static Future<void> warning(
    BuildContext context, {
    required String title,
    String? message,
    Widget? body,
    String confirmLabel = 'Continue',
    String cancelLabel = 'Cancel',
    VoidCallback? onConfirm,
    VoidCallback? onCancel,
  }) {
    return show(context, config: AppDialogConfig(
      type: AppDialogType.warning,
      title: title,
      message: message,
      body: body,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      onConfirm: onConfirm,
      onCancel: onCancel,
    ));
  }

  /// Info dialog (blue icon, single close button)
  static Future<void> info(
    BuildContext context, {
    required String title,
    String? message,
    Widget? body,
    String closeLabel = 'Got it',
    VoidCallback? onClose,
  }) {
    return show(context, config: AppDialogConfig(
      type: AppDialogType.info,
      title: title,
      message: message,
      body: body,
      confirmLabel: closeLabel,
      onConfirm: onClose,
    ));
  }

  /// Input dialog — single text field
  static Future<void> input(
    BuildContext context, {
    required String title,
    String? message,
    String? hint,
    String? initialValue,
    TextInputType keyboardType = TextInputType.text,
    String confirmLabel = 'Submit',
    String cancelLabel = 'Cancel',
    required void Function(String value) onSubmit,
    VoidCallback? onCancel,
    String? Function(String?)? validator,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black.withOpacity(0.45),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
      pageBuilder: (ctx, _, __) => _AppInputDialogWidget(
        title: title,
        message: message,
        hint: hint,
        initialValue: initialValue,
        keyboardType: keyboardType,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
        onSubmit: onSubmit,
        onCancel: onCancel,
        validator: validator,
      ),
    );
  }
}

// ─── Dialog Widget ────────────────────────────────────────────────────────────

class _AppDialogWidget extends StatelessWidget {
  final AppDialogConfig config;
  const _AppDialogWidget({required this.config});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);

    final typeData = _typeData(config.type);
    final hasTwoButtons = config.cancelLabel != null &&
        (config.type == AppDialogType.confirm ||
         config.type == AppDialogType.destructive ||
         config.type == AppDialogType.warning);

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          constraints: const BoxConstraints(maxWidth: 340),
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Icon + Title + Message ──────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                child: Column(
                  children: [
                    // Icon badge
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: typeData.iconBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(typeData.icon, color: typeData.iconColor, size: 24),
                    ),
                    const SizedBox(height: 16),
                    // Title
                    Text(
                      config.title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                        height: 1.3,
                      ),
                    ),
                    // Message
                    if (config.message != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        config.message!,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: isDark ? const Color(0xFF9E9E9E) : AppColors.textSecondary,
                          height: 1.5,
                        ),
                      ),
                    ],
                    // Custom body
                    if (config.body != null) ...[
                      const SizedBox(height: 16),
                      config.body!,
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // ── Divider ─────────────────────────────────────────────────
              Divider(height: 1, color: borderColor),
              // ── Buttons ─────────────────────────────────────────────────
              if (hasTwoButtons)
                _TwoButtonRow(
                  config: config,
                  typeData: typeData,
                  isDark: isDark,
                  borderColor: borderColor,
                )
              else
                _SingleButtonRow(
                  config: config,
                  typeData: typeData,
                  isDark: isDark,
                ),
            ],
          ),
        ),
      ),
    );
  }

  _TypeData _typeData(AppDialogType type) {
    switch (type) {
      case AppDialogType.confirm:
        return _TypeData(
          icon: LucideIcons.helpCircle,
          iconColor: AppColors.primary,
          iconBg: AppColors.primary.withOpacity(0.10),
          confirmColor: AppColors.primary,
        );
      case AppDialogType.destructive:
        return _TypeData(
          icon: LucideIcons.alertTriangle,
          iconColor: AppColors.danger,
          iconBg: AppColors.danger.withOpacity(0.10),
          confirmColor: AppColors.danger,
        );
      case AppDialogType.success:
        return _TypeData(
          icon: LucideIcons.checkCircle,
          iconColor: AppColors.success,
          iconBg: AppColors.success.withOpacity(0.10),
          confirmColor: AppColors.success,
        );
      case AppDialogType.error:
        return _TypeData(
          icon: LucideIcons.xCircle,
          iconColor: AppColors.danger,
          iconBg: AppColors.danger.withOpacity(0.10),
          confirmColor: AppColors.primary,
        );
      case AppDialogType.warning:
        return _TypeData(
          icon: LucideIcons.alertCircle,
          iconColor: AppColors.warning,
          iconBg: AppColors.warning.withOpacity(0.10),
          confirmColor: AppColors.warning,
        );
      case AppDialogType.info:
        return _TypeData(
          icon: LucideIcons.info,
          iconColor: AppColors.primary,
          iconBg: AppColors.primary.withOpacity(0.10),
          confirmColor: AppColors.primary,
        );
      case AppDialogType.input:
        return _TypeData(
          icon: LucideIcons.edit3,
          iconColor: AppColors.primary,
          iconBg: AppColors.primary.withOpacity(0.10),
          confirmColor: AppColors.primary,
        );
    }
  }
}

class _TypeData {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final Color confirmColor;
  const _TypeData({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.confirmColor,
  });
}

// ─── Two-button row (Cancel | Confirm) ───────────────────────────────────────

class _TwoButtonRow extends StatelessWidget {
  final AppDialogConfig config;
  final _TypeData typeData;
  final bool isDark;
  final Color borderColor;

  const _TwoButtonRow({
    required this.config,
    required this.typeData,
    required this.isDark,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          // Cancel
          Expanded(
            child: _DialogButton(
              label: config.cancelLabel ?? 'Cancel',
              onTap: () {
                Navigator.of(context).pop();
                config.onCancel?.call();
              },
              color: isDark ? const Color(0xFF9E9E9E) : AppColors.textSecondary,
              filled: false,
              isDark: isDark,
            ),
          ),
          VerticalDivider(width: 1, color: borderColor),
          // Confirm
          Expanded(
            child: _DialogButton(
              label: config.confirmLabel ?? 'Confirm',
              onTap: () {
                Navigator.of(context).pop();
                config.onConfirm?.call();
              },
              color: typeData.confirmColor,
              filled: false,
              isDark: isDark,
              bold: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Single-button row ────────────────────────────────────────────────────────

class _SingleButtonRow extends StatelessWidget {
  final AppDialogConfig config;
  final _TypeData typeData;
  final bool isDark;

  const _SingleButtonRow({
    required this.config,
    required this.typeData,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return _DialogButton(
      label: config.confirmLabel ?? 'OK',
      onTap: () {
        Navigator.of(context).pop();
        config.onConfirm?.call();
      },
      color: typeData.confirmColor,
      filled: false,
      isDark: isDark,
      bold: true,
    );
  }
}

// ─── Dialog Button ────────────────────────────────────────────────────────────

class _DialogButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final Color color;
  final bool filled;
  final bool isDark;
  final bool bold;

  const _DialogButton({
    required this.label,
    required this.onTap,
    required this.color,
    required this.filled,
    required this.isDark,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(22)),
        child: Container(
          height: 52,
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Input Dialog Widget ──────────────────────────────────────────────────────

class _AppInputDialogWidget extends StatefulWidget {
  final String title;
  final String? message;
  final String? hint;
  final String? initialValue;
  final TextInputType keyboardType;
  final String confirmLabel;
  final String cancelLabel;
  final void Function(String value) onSubmit;
  final VoidCallback? onCancel;
  final String? Function(String?)? validator;

  const _AppInputDialogWidget({
    required this.title,
    this.message,
    this.hint,
    this.initialValue,
    required this.keyboardType,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onSubmit,
    this.onCancel,
    this.validator,
  });

  @override
  State<_AppInputDialogWidget> createState() => _AppInputDialogWidgetState();
}

class _AppInputDialogWidgetState extends State<_AppInputDialogWidget> {
  late final TextEditingController _ctrl;
  final _formKey = GlobalKey<FormState>();
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);
    final inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: isDark ? const Color(0xFF333333) : AppColors.border),
    );

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 320,
          constraints: const BoxConstraints(maxWidth: 340),
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                blurRadius: 40,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: GoogleFonts.inter(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                      ),
                      if (widget.message != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          widget.message!,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: isDark ? const Color(0xFF9E9E9E) : AppColors.textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _ctrl,
                        keyboardType: widget.keyboardType,
                        autofocus: true,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          color: isDark ? Colors.white : AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: widget.hint,
                          hintStyle: GoogleFonts.inter(
                            fontSize: 14,
                            color: isDark ? const Color(0xFF666666) : AppColors.textSecondary,
                          ),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF2A2A2A) : AppColors.surfaceAlt,
                          border: inputBorder,
                          enabledBorder: inputBorder,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: AppColors.danger),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          errorText: _error,
                        ),
                        validator: widget.validator,
                        onFieldSubmitted: (_) => _submit(),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: borderColor),
              IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: _DialogButton(
                        label: widget.cancelLabel,
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onCancel?.call();
                        },
                        color: isDark ? const Color(0xFF9E9E9E) : AppColors.textSecondary,
                        filled: false,
                        isDark: isDark,
                      ),
                    ),
                    VerticalDivider(width: 1, color: borderColor),
                    Expanded(
                      child: _DialogButton(
                        label: widget.confirmLabel,
                        onTap: _submit,
                        color: AppColors.primary,
                        filled: false,
                        isDark: isDark,
                        bold: true,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (widget.validator != null) {
      final err = widget.validator!(_ctrl.text);
      if (err != null) {
        setState(() => _error = err);
        return;
      }
    }
    final value = _ctrl.text.trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop();
    widget.onSubmit(value);
  }
}

// ─── AppToast — Global overlay toast (always above modals/sheets/dialogs) ─────
//
// Delegates to GlobalToast which inserts into the root Navigator overlay,
// so toasts are always visible regardless of what's currently presented.

class AppToast {
  AppToast._();

  static void success(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    GlobalToast.success(context, message, duration: duration);
  }

  static void error(BuildContext context, String message, {Duration duration = const Duration(seconds: 4)}) {
    GlobalToast.error(context, message, duration: duration);
  }

  static void warning(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    GlobalToast.warning(context, message, duration: duration);
  }

  static void info(BuildContext context, String message, {Duration duration = const Duration(seconds: 3)}) {
    GlobalToast.info(context, message, duration: duration);
  }
}

// ─── AppBottomSheet — Premium bottom sheet wrapper ────────────────────────────

class AppBottomSheet {
  AppBottomSheet._();

  /// Show a premium bottom sheet with consistent styling
  static Future<T?> show<T>(
    BuildContext context, {
    required Widget child,
    bool isScrollControlled = true,
    bool isDismissible = true,
    String? title,
  }) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: isScrollControlled,
      isDismissible: isDismissible,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _AppBottomSheetWrapper(title: title, child: child),
    );
  }
}

class _AppBottomSheetWrapper extends StatelessWidget {
  final String? title;
  final Widget child;

  const _AppBottomSheetWrapper({this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2A2A2A) : const Color(0xFFF0F0F0);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: borderColor, width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF444444) : const Color(0xFFDDDDDD),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          if (title != null) ...[
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title!,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      LucideIcons.x,
                      size: 18,
                      color: isDark ? const Color(0xFF9E9E9E) : AppColors.textSecondary,
                    ),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: borderColor),
          ] else
            const SizedBox(height: 4),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20, 16, 20,
                MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}
