import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_update_service.dart';
import '../theme.dart';

/// Overlays a full-screen force-update dialog on top of [child] when
/// [AppUpdateService.instance.updateAvailable] is true.
/// Wrap [MaterialApp.builder]'s child with this widget.
class UpdateBannerOverlay extends StatelessWidget {
  final Widget child;

  const UpdateBannerOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppUpdateService.instance.updateAvailable,
      builder: (context, hasUpdate, _) {
        return Stack(
          children: [
            child,
            if (hasUpdate) const _ForceUpdateDialog(),
          ],
        );
      },
    );
  }
}

class _ForceUpdateDialog extends StatefulWidget {
  const _ForceUpdateDialog();

  @override
  State<_ForceUpdateDialog> createState() => _ForceUpdateDialogState();
}

class _ForceUpdateDialogState extends State<_ForceUpdateDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? AppColors.surfaceDark : AppColors.surface;
    final borderColor = isDark ? AppColors.borderDark : AppColors.border;
    final textPrimary =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimary;
    final textSecondary =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondary;
    final primary = isDark ? AppColors.primaryOnDark : AppColors.primary;

    return Positioned.fill(
      child: FadeTransition(
        opacity: _fade,
        child: Container(
          color: const Color(0x99000000),
          child: Center(
            child: ScaleTransition(
              scale: _scale,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xl,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(AppColors.heroRadius),
                    border: Border.all(color: borderColor),
                    boxShadow: AppColors.floatingShadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: primary.withOpacity(0.10),
                          borderRadius:
                              BorderRadius.circular(AppColors.cardRadius),
                        ),
                        child: Icon(
                          Icons.system_update_rounded,
                          color: primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Update Available',
                        style: GoogleFonts.inter(
                          color: textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'A new version of Trade Kosh is ready.\nUpdate now to get the latest features.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          color: textSecondary,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton.icon(
                          onPressed: AppUpdateService.reload,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(
                            'Update Now',
                            style: GoogleFonts.inter(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppColors.cardRadius),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
