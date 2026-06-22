//
//  about_view.dart
//
//  关于 — app identity (penguin icon, name, version) plus a tappable Telegram
//  channel link (t.me/mithka) that resolves in-app via the link handler.
//

import 'package:flutter/material.dart';

import '../chat/link_handler.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';

class AboutView extends StatelessWidget {
  const AboutView({super.key});

  static const _channelUrl = 'https://t.me/mithka';

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '关于', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 32, 12, 24),
              children: [
                Center(
                  child: Column(
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          gradient: AppTheme.brandGradient,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Center(
                          child: Text('🐧', style: TextStyle(fontSize: 46)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Mithkal',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: c.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '版本 1.0.0',
                        style: TextStyle(fontSize: 13, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Container(
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => openLink(context, _channelUrl),
                    child: SizedBox(
                      height: 52,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(
                              sfIcon('paperplane.fill'),
                              size: 20,
                              color: AppTheme.brand,
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Telegram 频道',
                              style: TextStyle(
                                fontSize: 16,
                                color: c.textPrimary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              't.me/mithka',
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              sfIcon('chevron.right'),
                              size: 14,
                              color: c.textTertiary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
