import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme.dart';

/// Full-screen error state shown when the backend is unreachable.
///
/// Used by Dashboard, Market Watch, Portfolio, and any screen that
/// requires live data. Shows a clear message and a retry button.
class BackendErrorWidget extends StatelessWidget {
  const BackendErrorWidget({
    super.key,
    this.message,
    this.onRetry,
    this.compact = false,
  });

  final String? message;
  final VoidCallback? onRetry;

  /// If true, renders a smaller inline card instead of full-screen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) return _CompactError(message: message, onRetry: onRetry);
    return _FullScreenError(message: message, onRetry: onRetry);
  }
}

// ── Full-screen ───────────────────────────────────────────────────────────────

class _FullScreenError extends StatelessWidget {
  const _FullScreenError({this.message, this.onRetry});
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                LucideIcons.wifiOff,
                size: 40,
                color: AppColors.danger,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message?.isNotEmpty == true
                  ? message!
                  : 'Unable to reach the market data server.\nPlease check your connection and try again.',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            if (onRetry != null)
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('Try Again'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Compact inline card ───────────────────────────────────────────────────────

class _CompactError extends StatelessWidget {
  const _CompactError({this.message, this.onRetry});
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.06),
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(color: AppColors.danger.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          const Icon(
            LucideIcons.alertCircle,
            size: 18,
            color: AppColors.danger,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message?.isNotEmpty == true
                  ? message!
                  : 'Market data unavailable. Please try again later.',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ],
      ),
    );
  }
}

/// Loading shimmer shown while waiting for first data from backend.
class BackendLoadingWidget extends StatelessWidget {
  const BackendLoadingWidget({super.key, this.message});
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            message ?? 'Loading market data...',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
