import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';

class FaqItemData {
  final String question;
  final String answer;
  const FaqItemData(this.question, this.answer);
}

class FaqAccordion extends StatefulWidget {
  final List<FaqItemData> items;
  const FaqAccordion({super.key, required this.items});

  @override
  State<FaqAccordion> createState() => _FaqAccordionState();
}

class _FaqAccordionState extends State<FaqAccordion> {
  int? _openIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < widget.items.length; i++)
          _FaqTile(
            data: widget.items[i],
            open: _openIndex == i,
            onTap: () => setState(() => _openIndex = _openIndex == i ? null : i),
          ),
      ],
    );
  }
}

class _FaqTile extends StatelessWidget {
  final FaqItemData data;
  final bool open;
  final VoidCallback onTap;

  const _FaqTile({required this.data, required this.open, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.cardRadius),
        border: Border.all(
          color: open ? AppColors.primary.withValues(alpha: 0.35) : AppColors.border,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      data.question,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      LucideIcons.chevronDown,
                      size: 20,
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  data.answer,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.6,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            crossFadeState:
                open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}
