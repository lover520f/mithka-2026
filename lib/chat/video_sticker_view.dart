//
//  video_sticker_view.dart
//
//  Plays a Telegram `.webm` (VP9 + alpha) video sticker, looping + muted. Decoding
//  goes through the MDK/FFmpeg backend registered in main() (`fvp`), which handles
//  VP8/VP9 transparent WebM — so the sticker animates AND keeps its transparency,
//  with no FFmpeg→WebP transcode. One controller per visible bubble.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';

class VideoStickerView extends StatefulWidget {
  const VideoStickerView({super.key, required this.file, this.onReady});
  final TdFileRef file;
  final VoidCallback? onReady;

  @override
  State<VideoStickerView> createState() => _VideoStickerViewState();
}

class _VideoStickerViewState extends State<VideoStickerView> {
  VideoPlayerController? _controller;
  int? _loadedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VideoStickerView old) {
    super.didUpdateWidget(old);
    _load();
  }

  Future<void> _load() async {
    final ref = widget.file;
    if (_loadedId == ref.id) return;
    _loadedId = ref.id;

    final old = _controller;
    if (old != null) {
      _controller = null;
      if (mounted) setState(() {});
      await old.dispose();
    }

    final path = await TdFileCenter.shared.path(ref.id);
    if (!mounted || path == null || _loadedId != ref.id) return;

    final c = VideoPlayerController.file(File(path));
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
    } catch (_) {
      await c.dispose();
      return;
    }
    if (!mounted || _loadedId != ref.id) {
      await c.dispose();
      return;
    }
    setState(() => _controller = c);
    widget.onReady?.call();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) return const SizedBox.expand();
    return VideoPlayer(c);
  }
}
