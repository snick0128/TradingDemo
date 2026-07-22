import 'dart:html' as html;

import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../theme.dart';
import '../../utils/responsive.dart';
import '../widgets/marketing_scaffold.dart';
import '../widgets/section.dart';

const _supportEmail = 'support@tradekosh.com';

class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isDesktop = layoutForWidth(width) == AppLayoutBreakpoint.desktop;

    return MarketingScaffold(
      path: '/contact',
      seoTitle: 'Contact Us — Trade Kosh',
      seoDescription:
          'Get in touch with the Trade Kosh team for support, feedback, or '
          'partnership queries about our paper trading and education '
          'platform.',
      child: Section(
        child: Column(
          children: [
            const SectionHeading(
              eyebrow: 'Contact',
              title: 'We\'d love to hear from you',
              subtitle:
                  'Questions about the Platform, a course, or your account? '
                  'Send us a message and our team will get back to you.',
            ),
            const SizedBox(height: 48),
            isDesktop
                ? IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: const [
                        Expanded(child: _ContactInfo()),
                        SizedBox(width: 32),
                        Expanded(flex: 2, child: _ContactForm()),
                      ],
                    ),
                  )
                : const Column(
                    children: [_ContactInfo(), SizedBox(height: 32), _ContactForm()],
                  ),
          ],
        ),
      ),
    );
  }
}

class _ContactInfo extends StatelessWidget {
  const _ContactInfo();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Trade Kosh',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        const SizedBox(height: 8),
        const Text(
          'Paper trading and stock market education platform.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 24),
        _infoRow(LucideIcons.mail, 'Email', _supportEmail),
        const SizedBox(height: 16),
        _infoRow(LucideIcons.clock, 'Business Hours', 'Mon–Sat, 9:00 AM – 6:00 PM IST'),
        const SizedBox(height: 16),
        _infoRow(LucideIcons.mapPin, 'Office', 'Trade Kosh HQ, Mumbai, Maharashtra, India'),
        const SizedBox(height: 24),
        Container(
          height: 160,
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppColors.cardRadius),
            border: Border.all(color: AppColors.border),
          ),
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(LucideIcons.map, size: 26, color: AppColors.textSecondary),
              SizedBox(height: 8),
              Text('Map preview placeholder', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
              Text(value, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContactForm extends StatefulWidget {
  const _ContactForm();

  @override
  State<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends State<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  bool _submitted = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _subjectCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;

    final subject = Uri.encodeComponent(
      _subjectCtrl.text.isNotEmpty ? _subjectCtrl.text : 'Trade Kosh Support Request',
    );
    final body = Uri.encodeComponent(
      'Name: ${_nameCtrl.text}\nEmail: ${_emailCtrl.text}\n\n${_messageCtrl.text}',
    );
    html.window.open('mailto:$_supportEmail?subject=$subject&body=$body', '_blank');

    setState(() => _submitted = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppColors.heroRadius),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.checkCircle2, size: 36, color: AppColors.success),
            const SizedBox(height: 16),
            const Text('Your email app should now be open', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 8),
            const Text(
              'Just hit send from your email client and we\'ll get back to you shortly.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextButton(onPressed: () => setState(() => _submitted = false), child: const Text('Send another message')),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppColors.heroRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label('Name'),
            TextFormField(
              controller: _nameCtrl,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null,
              decoration: const InputDecoration(hintText: 'Your full name'),
            ),
            const SizedBox(height: 16),
            _label('Email'),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Please enter your email';
                if (!v.contains('@') || !v.contains('.')) return 'Please enter a valid email';
                return null;
              },
              decoration: const InputDecoration(hintText: 'you@example.com'),
            ),
            const SizedBox(height: 16),
            _label('Subject'),
            TextFormField(
              controller: _subjectCtrl,
              decoration: const InputDecoration(hintText: 'How can we help?'),
            ),
            const SizedBox(height: 16),
            _label('Message'),
            TextFormField(
              controller: _messageCtrl,
              maxLines: 5,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a message' : null,
              decoration: const InputDecoration(hintText: 'Tell us more...'),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: const Text('Send Message'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
    );
  }
}
