//
//  sticker_preview.dart
//
//  Renders a StickerItem at preview size, animated by format: .tgs → Lottie,
//  .webm → fvp (video_player), .webp/other → its static thumbnail. Shared by the
//  sticker picker grid, the set-icon tabs, and the 表情详情 set-detail page so they
//  all animate consistently (instead of showing a frozen thumbnail).
//

import 'package:flutter/material.dart';

import '../components/photo_avatar.dart'; // TDImage
import '../tdlib/td_models.dart';
import 'animated_sticker_view.dart';
import 'sticker_item.dart';
import 'video_sticker_view.dart';

class StickerPreview extends StatelessWidget {
  const StickerPreview({super.key, required this.item, this.cornerRadius = 6});
  final StickerItem item;
  final double cornerRadius;

  @override
  Widget build(BuildContext context) {
    final file = TdFileRef(id: item.id);
    if (item.isAnimated) return AnimatedStickerView(file: file);
    if (item.isVideo) return VideoStickerView(file: file);
    if (item.thumb != null) {
      return TDImage(
        photo: item.thumb,
        cornerRadius: cornerRadius,
        fit: BoxFit.contain,
      );
    }
    return Center(
      child: Text(
        item.emoji.isEmpty ? '🎴' : item.emoji,
        style: const TextStyle(fontSize: 30),
      ),
    );
  }
}
