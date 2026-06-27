//
//  topic_chat_view.dart
//
//  Forum/topic chat surface. This is not the normal Telegram chat screen:
//  it presents a topic tab strip and post feed for chats that TDLib exposes as
//  view_as_topics.
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../chat/chat_members_view.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import '../chat/rich_text_format.dart';

class TopicChatView extends StatefulWidget {
  const TopicChatView({
    super.key,
    required this.chat,
    this.initialThreadId,
    this.initialMessageId,
    this.showBackButton = true,
  });

  final ChatSummary chat;
  final int? initialThreadId;
  final int? initialMessageId;
  final bool showBackButton;

  @override
  State<TopicChatView> createState() => _TopicChatViewState();
}

class _ForumTopic {
  const _ForumTopic({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.isPinned,
    required this.isMuted,
  });

  final int id;
  final String name;
  final ChatMessage lastMessage;
  final bool isPinned;
  final bool isMuted;
}

class _TopicPost {
  const _TopicPost({required this.topic, required this.message});

  final _ForumTopic topic;
  final ChatMessage message;
}

class _SenderInfo {
  const _SenderInfo({required this.name, this.photo});

  final String name;
  final TdFileRef? photo;
}

class _TopicChatViewState extends State<TopicChatView> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  final _topics = <_ForumTopic>[];
  final _topicMessages = <int, List<ChatMessage>>{};
  final _loadingThreads = <int>{};
  final _senderCache = <int, _SenderInfo>{};
  bool _loading = true;
  int? _selectedThreadId;

  @override
  void initState() {
    super.initState();
    _selectedThreadId = widget.initialThreadId;
    _loadTopics();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  Future<void> _loadTopics() async {
    setState(() => _loading = true);
    try {
      final response = await TdClient.shared.query({
        '@type': 'getForumTopics',
        'chat_id': widget.chat.id,
        'query': '',
        'offset_date': 0,
        'offset_message_id': 0,
        'offset_forum_topic_id': 0,
        'limit': 80,
      });
      final rawTopics =
          response.objects('topics') ?? const <Map<String, dynamic>>[];
      final next = <_ForumTopic>[];
      for (final topic in rawTopics) {
        final info = topic.obj('info') ?? topic;
        final last = topic.obj('last_message');
        final message = last == null ? null : TDParse.message(last);
        if (message == null || message.isService) continue;
        next.add(
          _ForumTopic(
            id:
                info.int64('message_thread_id') ??
                topic.int64('message_thread_id') ??
                message.id,
            name: info.str('name') ?? topic.str('name') ?? '话题',
            lastMessage: message,
            isPinned: topic.boolean('is_pinned') ?? false,
            isMuted:
                (topic.obj('notification_settings')?.integer('mute_for') ?? 0) >
                0,
          ),
        );
      }
      next.sort((a, b) => b.lastMessage.date.compareTo(a.lastMessage.date));
      _topics
        ..clear()
        ..addAll(next);
      if (_selectedThreadId != null &&
          !_topics.any((topic) => topic.id == _selectedThreadId)) {
        _selectedThreadId = null;
      }
      await _loadVisibleThreads();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadVisibleThreads() async {
    final selected = _selectedThreadId;
    final threads = selected == null
        ? _topics.take(12)
        : _topics.where((topic) => topic.id == selected);
    await Future.wait(threads.map(_loadThreadMessages));
  }

  Future<void> _loadThreadMessages(_ForumTopic topic) async {
    if (_topicMessages.containsKey(topic.id) ||
        _loadingThreads.contains(topic.id)) {
      return;
    }
    _loadingThreads.add(topic.id);
    try {
      final response = await TdClient.shared.query({
        '@type': 'getMessageThreadHistory',
        'chat_id': widget.chat.id,
        'message_id': topic.id,
        'from_message_id': 0,
        'offset': 0,
        'limit': _selectedThreadId == null ? 6 : 40,
      });
      final messages =
          (response.objects('messages') ?? const <Map<String, dynamic>>[])
              .map(TDParse.message)
              .whereType<ChatMessage>()
              .where((message) => !message.isService)
              .where((message) => message.replyToMessageId == null)
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date));
      _topicMessages[topic.id] = messages.isEmpty
          ? [topic.lastMessage]
          : messages;
      _resolveSenders(_topicMessages[topic.id]!);
    } catch (_) {
      _topicMessages[topic.id] = [topic.lastMessage];
      _resolveSenders(_topicMessages[topic.id]!);
    } finally {
      _loadingThreads.remove(topic.id);
      if (mounted) setState(() {});
    }
  }

  void _selectTopic(int? threadId) {
    setState(() => _selectedThreadId = threadId);
    _loadVisibleThreads();
    if (_scroll.hasClients) {
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  List<_TopicPost> get _posts {
    final selected = _selectedThreadId;
    final posts = <_TopicPost>[];
    for (final topic in _topics) {
      if (selected != null && topic.id != selected) continue;
      final messages = _topicMessages[topic.id] ?? [topic.lastMessage];
      for (final message in messages) {
        posts.add(_TopicPost(topic: topic, message: message));
      }
    }
    posts.sort((a, b) => b.message.date.compareTo(a.message.date));
    return posts;
  }

  Future<void> _resolveSenders(List<ChatMessage> messages) async {
    for (final message in messages) {
      final id = message.senderId;
      if (id == null || _senderCache.containsKey(id)) continue;
      try {
        if (id > 0) {
          final user = await TdClient.shared.query({
            '@type': 'getUser',
            'user_id': id,
          });
          _senderCache[id] = _SenderInfo(
            name: TDParse.userName(user),
            photo: TDParse.smallPhoto(user.obj('profile_photo')),
          );
        } else {
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': id,
          });
          _senderCache[id] = _SenderInfo(
            name: chat.str('title') ?? '用户',
            photo: TDParse.smallPhoto(chat.obj('photo')),
          );
        }
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  Future<void> _sendPostText(String rawText) async {
    final parsed = parseTelegramMarkdown(rawText.trim());
    final text = parsed.text;
    if (text.isEmpty) return;
    final threadId = _selectedThreadId;
    try {
      final request = {
        '@type': 'sendMessage',
        'chat_id': widget.chat.id,
        'input_message_content': {
          '@type': 'inputMessageText',
          'text': {
            '@type': 'formattedText',
            'text': text,
            if (parsed.entities.isNotEmpty) 'entities': parsed.entities,
          },
        },
      };
      if (threadId != null) request['message_thread_id'] = threadId;
      await TdClient.shared.query(request);
      _input.clear();
      _topicMessages.clear();
      await _loadTopics();
    } catch (_) {}
  }

  Future<void> _openComposer() async {
    final result = await Navigator.of(context).push<_TopicComposerResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _TopicRichTextComposer(initialText: _input.text),
      ),
    );
    if (result == null) return;
    _input.text = result.text;
    if (result.media.isEmpty) {
      await _sendPostText(result.text);
    } else {
      await _sendPostMedia(result);
    }
  }

  Future<void> _sendPostMedia(_TopicComposerResult result) async {
    final threadId = _selectedThreadId;
    for (var i = 0; i < result.media.length; i++) {
      final file = result.media[i];
      final caption = i == 0
          ? parseTelegramMarkdown(result.text.trim()).toTdJson()
          : null;
      final isVideo = _isVideoPath(file.path);
      final request = {
        '@type': 'sendMessage',
        'chat_id': widget.chat.id,
        'input_message_content': {
          '@type': isVideo ? 'inputMessageVideo' : 'inputMessagePhoto',
          isVideo ? 'video' : 'photo': {
            '@type': isVideo ? 'inputVideo' : 'inputPhoto',
            isVideo ? 'video' : 'photo': {
              '@type': 'inputFileLocal',
              'path': file.path,
            },
          },
          if (caption != null && (caption['text'] as String).isNotEmpty)
            'caption': caption,
        },
      };
      if (threadId != null) request['message_thread_id'] = threadId;
      await TdClient.shared.query(request);
    }
    _input.clear();
    _topicMessages.clear();
    await _loadTopics();
  }

  bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm');
  }

  void _openSearch() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TopicSearchView(chat: widget.chat, topics: _topics),
      ),
    );
  }

  void _openSettings() {
    _ForumTopic? currentTopic;
    final selected = _selectedThreadId;
    if (selected != null) {
      for (final topic in _topics) {
        if (topic.id == selected) {
          currentTopic = topic;
          break;
        }
      }
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _TopicChannelSettingsView(
          chat: widget.chat,
          currentTopic: currentTopic,
          topics: _topics,
          onOpenMessages: () {
            Navigator.of(context).pop();
            final topic = currentTopic;
            if (topic != null) _selectTopic(topic.id);
          },
          onTopicChanged: () async {
            _topicMessages.clear();
            await _loadTopics();
          },
        ),
      ),
    );
  }

  void _openComments(_TopicPost post, _SenderInfo? sender) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TopicCommentsSheet(
        chatId: widget.chat.id,
        post: post,
        sender: sender,
        loadSender: _loadSender,
      ),
    );
  }

  Future<void> _addReaction(_TopicPost post, String emoji) async {
    try {
      await TdClient.shared.query({
        '@type': 'addMessageReaction',
        'chat_id': widget.chat.id,
        'message_id': post.message.id,
        'reaction_type': {'@type': 'reactionTypeEmoji', 'emoji': emoji},
        'is_big': false,
        'update_recent_reactions': true,
      });
      _topicMessages.clear();
      await _loadTopics();
    } catch (_) {}
  }

  void _showReactionPicker(_TopicPost post) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final c = context.colors;
        const reactions = ['❤️', '👍', '😂', '😮', '😢', '🔥'];
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: c.card,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                for (final reaction in reactions)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      Navigator.of(context).pop();
                      _addReaction(post, reaction);
                    },
                    child: Text(reaction, style: const TextStyle(fontSize: 28)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<_SenderInfo?> _loadSender(int? id) async {
    if (id == null) return null;
    final cached = _senderCache[id];
    if (cached != null) return cached;
    try {
      if (id > 0) {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': id,
        });
        final info = _SenderInfo(
          name: TDParse.userName(user),
          photo: TDParse.smallPhoto(user.obj('profile_photo')),
        );
        _senderCache[id] = info;
        return info;
      }
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': id,
      });
      final info = _SenderInfo(
        name: chat.str('title') ?? '用户',
        photo: TDParse.smallPhoto(chat.obj('photo')),
      );
      _senderCache[id] = info;
      return info;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _header(),
          _topicTabs(),
          if (_selectedThreadId == null && widget.chat.lastMessage.isNotEmpty)
            _pinnedLine(),
          Expanded(child: _content()),
          _bottomComposer(),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    final top = MediaQuery.of(context).padding.top;
    return Container(
      height: top + 48,
      padding: EdgeInsets.only(top: top),
      decoration: BoxDecoration(
        color: c.navBar,
        image: DecorationImage(
          image: const AssetImage('assets/app_icon.png'),
          fit: BoxFit.cover,
          opacity: 0.04,
        ),
      ),
      child: Row(
        children: [
          if (widget.showBackButton)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).pop(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Icon(
                  sfIcon('chevron.left'),
                  size: 24,
                  color: c.textPrimary,
                ),
              ),
            )
          else
            const SizedBox(width: AppSpacing.sm),
          PhotoAvatar(
            title: widget.chat.title,
            photo: widget.chat.photo,
            size: 32,
            square: true,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.chat.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: c.textPrimary,
                  ),
                ),
                Text(
                  _topics.isEmpty ? '话题群聊' : '${_topics.length} 个话题',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openSearch,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                sfIcon('magnifyingglass'),
                size: 25,
                color: c.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xl),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openSettings,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                sfIcon('line.3.horizontal'),
                size: 25,
                color: c.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xl),
        ],
      ),
    );
  }

  Widget _topicTabs() {
    final c = context.colors;
    final tabs = [
      (id: null, title: '全部'),
      ..._topics.take(8).map((topic) => (id: topic.id, title: topic.name)),
    ];
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final selected = tab.id == _selectedThreadId;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _selectTopic(tab.id),
            child: SizedBox(
              height: 52,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    tab.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: selected ? AppTheme.brand : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
        separatorBuilder: (_, _) => const SizedBox(width: 28),
        itemCount: tabs.length,
      ),
    );
  }

  Widget _pinnedLine() {
    final c = context.colors;
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.background,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Row(
        children: [
          Text('置顶 | ', style: TextStyle(fontSize: 15, color: c.textSecondary)),
          Expanded(
            child: Text(
              widget.chat.lastMessage,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15, color: c.textPrimary),
            ),
          ),
          Text('展开', style: TextStyle(fontSize: 14, color: c.textTertiary)),
        ],
      ),
    );
  }

  Widget _content() {
    final posts = _posts;
    if (_loading && posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (posts.isEmpty) {
      return Center(
        child: Text(
          '暂无更多内容',
          style: TextStyle(fontSize: 15, color: context.colors.textTertiary),
        ),
      );
    }
    return ListView.separated(
      controller: _scroll,
      padding: EdgeInsets.zero,
      itemCount: posts.length,
      separatorBuilder: (_, _) => const InsetDivider(leadingInset: 0),
      itemBuilder: (context, index) => _TopicPostRow(
        post: posts[index],
        sender: _senderCache[posts[index].message.senderId],
        onLike: () => _addReaction(posts[index], '❤️'),
        onPickReaction: () => _showReactionPicker(posts[index]),
        onComments: () => _openComments(
          posts[index],
          _senderCache[posts[index].message.senderId],
        ),
      ),
    );
  }

  Widget _bottomComposer() {
    final c = context.colors;
    return Material(
      color: c.navBar,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _openComposer,
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: c.searchFill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _input.text.trim().isEmpty ? '期待你的分享' : _input.text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: _input.text.trim().isEmpty
                            ? c.textTertiary
                            : c.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openComposer,
                child: Icon(
                  sfIcon('square.and.pencil'),
                  size: 26,
                  color: AppTheme.brand,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicPostRow extends StatelessWidget {
  const _TopicPostRow({
    required this.post,
    required this.onLike,
    required this.onPickReaction,
    required this.onComments,
    this.sender,
  });

  final _TopicPost post;
  final _SenderInfo? sender;
  final VoidCallback onLike;
  final VoidCallback onPickReaction;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final text = _displayText;
    final name = sender?.name.trim().isNotEmpty == true
        ? sender!.name.trim()
        : post.message.senderName ?? post.topic.name;
    return Container(
      color: c.background,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PhotoAvatar(title: name, photo: sender?.photo, size: 48),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateText.listLabel(post.message.date),
                      style: TextStyle(fontSize: 14, color: c.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (text.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              text,
              style: TextStyle(
                fontSize: 16,
                height: 1.35,
                color: c.textPrimary,
              ),
            ),
          ],
          if (post.message.image != null) ...[
            const SizedBox(height: 12),
            _PostImage(message: post.message),
            _ExtraReactions(message: post.message),
          ],
          const SizedBox(height: 13),
          _PostActions(
            message: post.message,
            onLike: onLike,
            onPickReaction: onPickReaction,
            onComments: onComments,
          ),
        ],
      ),
    );
  }

  String get _displayText {
    final text = post.message.text.trim();
    if (text.startsWith('[') && text.endsWith(']')) return '';
    return text;
  }
}

class _PostImage extends StatelessWidget {
  const _PostImage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width - 28;
    final height = _imageHeight(width);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: height,
        child: TDImage(
          photo: message.image,
          cornerRadius: 6,
          fit: BoxFit.cover,
          cacheWidth: (width * MediaQuery.of(context).devicePixelRatio).round(),
          cacheHeight: (height * MediaQuery.of(context).devicePixelRatio)
              .round(),
        ),
      ),
    );
  }

  double _imageHeight(double width) {
    final w = message.imageWidth;
    final h = message.imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return width * 0.62;
    final ratio = (h / w).clamp(0.45, 1.25);
    return width * ratio;
  }
}

class _PostActions extends StatelessWidget {
  const _PostActions({
    required this.message,
    required this.onLike,
    required this.onPickReaction,
    required this.onComments,
  });

  final ChatMessage message;
  final VoidCallback onLike;
  final VoidCallback onPickReaction;
  final VoidCallback onComments;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final likeCount = message.reactions.fold<int>(
      0,
      (sum, reaction) => reaction.emoji == '❤️' ? sum + reaction.count : sum,
    );
    return Row(
      children: [
        Text(
          '浏览 ${message.id.abs() % 900 + 10}',
          style: TextStyle(fontSize: 14, color: c.textTertiary),
        ),
        const Spacer(),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onLike,
          onLongPress: onPickReaction,
          child: Icon(sfIcon('heart'), size: 24, color: c.textPrimary),
        ),
        const SizedBox(width: 5),
        Text(
          '$likeCount',
          style: TextStyle(fontSize: 14, color: c.textPrimary),
        ),
        const SizedBox(width: 24),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onComments,
          child: Icon(sfIcon('bubble.left'), size: 24, color: c.textPrimary),
        ),
        const SizedBox(width: 5),
        Text(
          message.commentCount == 0 ? '' : '${message.commentCount}',
          style: TextStyle(fontSize: 14, color: c.textPrimary),
        ),
        const SizedBox(width: 24),
        Icon(
          sfIcon('arrowshape.turn.up.right'),
          size: 25,
          color: c.textPrimary,
        ),
      ],
    );
  }
}

class _ExtraReactions extends StatelessWidget {
  const _ExtraReactions({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final extra = message.reactions
        .where((reaction) => reaction.count > 0 && reaction.emoji != '❤️')
        .toList();
    if (extra.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final reaction in extra)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${reaction.emoji ?? '⭐'} ${reaction.count}',
                style: TextStyle(fontSize: 13, color: c.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopicComposerResult {
  const _TopicComposerResult({required this.text, required this.media});

  final String text;
  final List<XFile> media;
}

class _TopicRichTextComposer extends StatefulWidget {
  const _TopicRichTextComposer({required this.initialText});

  final String initialText;

  @override
  State<_TopicRichTextComposer> createState() => _TopicRichTextComposerState();
}

class _TopicRichTextComposerState extends State<_TopicRichTextComposer> {
  late final TextEditingController _controller;
  final _picker = ImagePicker();
  final _media = <XFile>[];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _wrap(String left, [String? right]) {
    right ??= left;
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final selected = value.text.substring(start, end);
    final next = value.text.replaceRange(start, end, '$left$selected$right');
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + left.length + selected.length,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('取消', style: TextStyle(color: c.textPrimary)),
                  ),
                  Expanded(
                    child: Text(
                      '分享',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(
                      _TopicComposerResult(
                        text: _controller.text,
                        media: List<XFile>.of(_media),
                      ),
                    ),
                    child: const Text('发布'),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.divider),
            _toolbar(c),
            _mediaStrip(c),
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: c.textPrimary,
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(16),
                  border: InputBorder.none,
                  hintText: '分享想法、图片说明或链接',
                  hintStyle: TextStyle(color: c.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(AppColors c) {
    return Container(
      height: 44,
      color: c.navBar,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _formatButton(c, 'B', () => _wrap('**')),
          _formatButton(c, 'I', () => _wrap('*')),
          _formatButton(c, 'U', () => _wrap('__')),
          _formatButton(c, 'S', () => _wrap('~~')),
          _formatButton(c, '</>', () => _wrap('`')),
          _formatButton(c, '引用', () => _wrap('> ', '')),
        ],
      ),
    );
  }

  Widget _mediaStrip(AppColors c) {
    if (_media.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _pickMedia,
          icon: Icon(sfIcon('photo'), size: 20),
          label: const Text('照片/视频'),
        ),
      );
    }
    return SizedBox(
      height: 94,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        scrollDirection: Axis.horizontal,
        itemCount: _media.length + (_media.length < 9 ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == _media.length) return _addMediaTile(c);
          return _mediaTile(c, index);
        },
      ),
    );
  }

  Widget _addMediaTile(AppColors c) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickMedia,
      child: Container(
        width: 84,
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(sfIcon('plus'), color: c.textTertiary),
      ),
    );
  }

  Widget _mediaTile(AppColors c, int index) {
    final item = _media[index];
    final isVideo =
        item.path.toLowerCase().endsWith('.mp4') ||
        item.path.toLowerCase().endsWith('.mov') ||
        item.path.toLowerCase().endsWith('.m4v') ||
        item.path.toLowerCase().endsWith('.webm');
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(item.path),
            width: 84,
            height: 84,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 84,
              height: 84,
              color: c.searchFill,
              child: Icon(
                isVideo ? sfIcon('play.rectangle') : sfIcon('photo'),
                color: c.textTertiary,
              ),
            ),
          ),
        ),
        if (isVideo)
          Positioned.fill(
            child: Center(
              child: Icon(sfIcon('play.fill'), color: Colors.white, size: 24),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _media.removeAt(index)),
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: Icon(sfIcon('xmark'), size: 12, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickMedia() async {
    try {
      final picked = await _picker.pickMultipleMedia();
      if (picked.isEmpty || !mounted) return;
      final remaining = 9 - _media.length;
      setState(() => _media.addAll(picked.take(remaining)));
    } catch (_) {}
  }

  Widget _formatButton(AppColors c, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        onPressed: onTap,
        child: Text(label, style: TextStyle(color: c.textPrimary)),
      ),
    );
  }
}

class _TopicCommentsSheet extends StatefulWidget {
  const _TopicCommentsSheet({
    required this.chatId,
    required this.post,
    required this.sender,
    required this.loadSender,
  });

  final int chatId;
  final _TopicPost post;
  final _SenderInfo? sender;
  final Future<_SenderInfo?> Function(int? id) loadSender;

  @override
  State<_TopicCommentsSheet> createState() => _TopicCommentsSheetState();
}

class _TopicCommentsSheetState extends State<_TopicCommentsSheet> {
  final _comments = <ChatMessage>[];
  final _senders = <int, _SenderInfo>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final response = await TdClient.shared.query({
        '@type': 'getMessageThreadHistory',
        'chat_id': widget.chatId,
        'message_id': widget.post.message.id,
        'from_message_id': 0,
        'offset': 0,
        'limit': 40,
      });
      final messages =
          (response.objects('messages') ?? const <Map<String, dynamic>>[])
              .map(TDParse.message)
              .whereType<ChatMessage>()
              .where(
                (message) =>
                    !message.isService &&
                    message.id != widget.post.message.id &&
                    _commentText(message).isNotEmpty,
              )
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      for (final message in messages) {
        final sender = await widget.loadSender(message.senderId);
        if (sender != null && message.senderId != null) {
          _senders[message.senderId!] = sender;
        }
      }
      if (!mounted) return;
      setState(() {
        _comments
          ..clear()
          ..addAll(messages);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _commentText(ChatMessage message) {
    final text = message.text.trim();
    if (text.startsWith('[') && text.endsWith(']')) return '';
    return text;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final height = MediaQuery.of(context).size.height * 0.72;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 54,
            height: 6,
            decoration: BoxDecoration(
              color: c.divider,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '评论 ${widget.post.message.commentCount}',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _comments.length,
                    itemBuilder: (context, index) {
                      final message = _comments[index];
                      final sender = _senders[message.senderId];
                      return _CommentRow(
                        message: message,
                        sender: sender,
                        fallbackName: widget.sender?.name ?? '用户',
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              decoration: BoxDecoration(
                color: c.navBar,
                border: Border(top: BorderSide(color: c.divider, width: 0.5)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 44,
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.searchFill,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '发言要友善',
                        style: TextStyle(fontSize: 15, color: c.textTertiary),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Icon(sfIcon('at'), size: 25, color: c.textPrimary),
                  const SizedBox(width: 14),
                  Icon(sfIcon('face.smiling'), size: 25, color: c.textPrimary),
                  const SizedBox(width: 14),
                  Icon(sfIcon('photo'), size: 25, color: c.textPrimary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommentRow extends StatelessWidget {
  const _CommentRow({
    required this.message,
    required this.fallbackName,
    this.sender,
  });

  final ChatMessage message;
  final _SenderInfo? sender;
  final String fallbackName;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = sender?.name.trim().isNotEmpty == true
        ? sender!.name
        : message.senderName ?? fallbackName;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhotoAvatar(title: name, photo: sender?.photo, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, color: c.textSecondary),
                ),
                const SizedBox(height: 5),
                Text(
                  message.text,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.35,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${DateText.listLabel(message.date)}  回复',
                  style: TextStyle(fontSize: 13, color: c.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(sfIcon('heart'), size: 22, color: c.textTertiary),
        ],
      ),
    );
  }
}

class _TopicSearchView extends StatefulWidget {
  const _TopicSearchView({required this.chat, required this.topics});

  final ChatSummary chat;
  final List<_ForumTopic> topics;

  @override
  State<_TopicSearchView> createState() => _TopicSearchViewState();
}

class _TopicSearchViewState extends State<_TopicSearchView> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<ChatMessage> _results = const [];
  bool _loading = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _changed(String value) {
    setState(() {});
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() => _results = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(value));
  }

  Future<void> _run(String query) async {
    setState(() => _loading = true);
    try {
      final response = await TdClient.shared.query({
        '@type': 'searchChatMessages',
        'chat_id': widget.chat.id,
        'query': query,
        'sender_id': null,
        'from_message_id': 0,
        'offset': 0,
        'limit': 50,
        'filter': {'@type': 'searchMessagesFilterEmpty'},
      });
      final results =
          (response.objects('messages') ?? const <Map<String, dynamic>>[])
              .map(TDParse.message)
              .whereType<ChatMessage>()
              .where((message) => !message.isService)
              .toList();
      if (!mounted || query != _controller.text) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 14, 12),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(sfIcon('chevron.left'), color: c.textPrimary),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.searchFill,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        onChanged: _changed,
                        style: TextStyle(fontSize: 16, color: c.textPrimary),
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          icon: Icon(
                            sfIcon('magnifyingglass'),
                            color: c.textTertiary,
                          ),
                          hintText: '搜索',
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: Icon(
                                    sfIcon('xmark.circle.fill'),
                                    color: c.textTertiary,
                                  ),
                                  onPressed: () {
                                    _controller.clear();
                                    _changed('');
                                  },
                                ),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('取消', style: TextStyle(color: AppTheme.brand)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 12),
              child: Row(
                children: [
                  _filterPill(c, '选择版块'),
                  const SizedBox(width: 10),
                  _filterPill(c, '选择时间'),
                  const Spacer(),
                  Text('最相关', style: TextStyle(color: c.textPrimary)),
                  const SizedBox(width: 3),
                  Icon(sfIcon('arrow.up.arrow.down'), size: 17),
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      itemCount: _results.length,
                      separatorBuilder: (_, _) => Divider(color: c.divider),
                      itemBuilder: (context, index) =>
                          _SearchResultRow(message: _results[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterPill(AppColors c, String text) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        border: Border.all(color: c.divider),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Row(
        children: [
          Text(text, style: TextStyle(fontSize: 14, color: c.textPrimary)),
          const SizedBox(width: 6),
          Icon(sfIcon('chevron.down'), size: 14, color: c.textPrimary),
        ],
      ),
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final name = message.senderName ?? '用户';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PhotoAvatar(title: name, photo: message.senderPhoto, size: 38),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                if (message.text.trim().isNotEmpty)
                  Text(
                    message.text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: c.textPrimary,
                    ),
                  ),
                if (message.image != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 160,
                      height: 92,
                      child: TDImage(
                        photo: message.image,
                        cornerRadius: 6,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      DateText.listLabel(message.date),
                      style: TextStyle(fontSize: 13, color: c.textTertiary),
                    ),
                    const Spacer(),
                    Text(
                      '${message.reactions.fold<int>(0, (sum, item) => sum + item.count)} 赞 · ${message.commentCount} 评',
                      style: TextStyle(fontSize: 13, color: c.textTertiary),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicMemberInfo {
  const _TopicMemberInfo({required this.name, this.photo});

  final String name;
  final TdFileRef? photo;
}

class _TopicChannelSettingsView extends StatefulWidget {
  const _TopicChannelSettingsView({
    required this.chat,
    required this.currentTopic,
    required this.topics,
    required this.onOpenMessages,
    required this.onTopicChanged,
  });

  final ChatSummary chat;
  final _ForumTopic? currentTopic;
  final List<_ForumTopic> topics;
  final VoidCallback onOpenMessages;
  final Future<void> Function() onTopicChanged;

  @override
  State<_TopicChannelSettingsView> createState() =>
      _TopicChannelSettingsViewState();
}

class _TopicChannelSettingsViewState extends State<_TopicChannelSettingsView> {
  final _members = <_TopicMemberInfo>[];
  int _memberCount = 0;
  bool _loadingMembers = true;
  late bool _topicPinned = widget.currentTopic?.isPinned ?? false;
  late bool _topicMuted = widget.currentTopic?.isMuted ?? false;

  _ForumTopic? get _topic => widget.currentTopic;

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': widget.chat.id,
      });
      final type = chat.obj('type');
      List<Map<String, dynamic>> raw = [];
      if (type?.type == 'chatTypeBasicGroup') {
        final gid = type?.int64('basic_group_id');
        if (gid != null) {
          final full = await TdClient.shared.query({
            '@type': 'getBasicGroupFullInfo',
            'basic_group_id': gid,
          });
          raw = full.objects('members') ?? const <Map<String, dynamic>>[];
          _memberCount = raw.length;
        }
      } else if (type?.type == 'chatTypeSupergroup') {
        final sgid = type?.int64('supergroup_id');
        if (sgid != null) {
          final result = await TdClient.shared.query({
            '@type': 'getSupergroupMembers',
            'supergroup_id': sgid,
            'filter': {'@type': 'supergroupMembersFilterRecent'},
            'offset': 0,
            'limit': 30,
          });
          raw = result.objects('members') ?? const <Map<String, dynamic>>[];
          _memberCount =
              result.integer('member_count') ??
              result.integer('total_count') ??
              raw.length;
        }
      }
      await _resolveMembers(raw);
    } catch (_) {
      _memberCount = _members.length;
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  Future<void> _resolveMembers(List<Map<String, dynamic>> raw) async {
    final result = <_TopicMemberInfo>[];
    for (final entry in raw.take(12)) {
      final memberId = entry.obj('member_id');
      if (memberId?.type != 'messageSenderUser') continue;
      final uid = memberId?.int64('user_id');
      if (uid == null) continue;
      try {
        final user = await TdClient.shared.query({
          '@type': 'getUser',
          'user_id': uid,
        });
        result.add(
          _TopicMemberInfo(
            name: TDParse.userName(user),
            photo: TDParse.smallPhoto(user.obj('profile_photo')),
          ),
        );
        if (mounted) {
          setState(() {
            _members
              ..clear()
              ..addAll(result);
          });
        }
      } catch (_) {}
    }
  }

  void _openMembers() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            ChatMembersView(chatId: widget.chat.id, title: widget.chat.title),
      ),
    );
  }

  Future<void> _setTopicPinned(bool value) async {
    final topic = _topic;
    if (topic == null) return;
    setState(() => _topicPinned = value);
    try {
      await TdClient.shared.query({
        '@type': 'toggleForumTopicIsPinned',
        'chat_id': widget.chat.id,
        'forum_topic_id': topic.id,
        'is_pinned': value,
      });
      await widget.onTopicChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() => _topicPinned = !value);
      showToast(context, '设置置顶失败');
    }
  }

  Future<void> _setTopicMuted(bool value) async {
    final topic = _topic;
    if (topic == null) return;
    setState(() => _topicMuted = value);
    try {
      await TdClient.shared.query({
        '@type': 'setForumTopicNotificationSettings',
        'chat_id': widget.chat.id,
        'forum_topic_id': topic.id,
        'notification_settings': {
          '@type': 'chatNotificationSettings',
          'use_default_mute_for': false,
          'mute_for': value ? 2147483647 : 0,
        },
      });
      await widget.onTopicChanged();
    } catch (_) {
      if (!mounted) return;
      setState(() => _topicMuted = !value);
      showToast(context, '设置免打扰失败');
    }
  }

  Future<void> _exitTopic() async {
    final topic = _topic;
    if (topic == null) return;
    final ok = await confirmDialog(
      context,
      title: '退出频道',
      message: '退出「${topic.name}」后将删除该话题频道。继续？',
      confirmText: '退出',
      destructive: true,
    );
    if (!ok) return;
    try {
      await TdClient.shared.query({
        '@type': 'deleteForumTopic',
        'chat_id': widget.chat.id,
        'forum_topic_id': topic.id,
      });
      await widget.onTopicChanged();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) showToast(context, '退出频道失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final topic = _topic;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 58,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(sfIcon('chevron.left'), color: c.textPrimary),
                  ),
                  Expanded(
                    child: Text(
                      '频道设置',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: Icon(
                      sfIcon('arrowshape.turn.up.right'),
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
                children: [
                  Row(
                    children: [
                      PhotoAvatar(
                        title: widget.chat.title,
                        photo: widget.chat.photo,
                        size: 72,
                        square: true,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.chat.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: c.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '频道号：${widget.chat.id.abs()}',
                              style: TextStyle(
                                fontSize: 14,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(sfIcon('qrcode'), size: 26, color: c.textPrimary),
                    ],
                  ),
                  const SizedBox(height: 22),
                  SettingsCard(
                    children: [
                      SettingsRow(
                        title: '频道成员',
                        value: _loadingMembers ? '加载中' : '$_memberCount人',
                        onTap: _openMembers,
                      ),
                      _memberStrip(c),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const SettingsCard(
                    children: [SettingsRow(title: '我的资料', value: 'ieb')],
                  ),
                  const SizedBox(height: 16),
                  SettingsCard(
                    children: [
                      SettingsRow(
                        title: '频道消息',
                        value: topic?.name ?? '全部话题',
                        onTap: widget.onOpenMessages,
                      ),
                      SettingsSwitchRow(
                        title: '设为置顶',
                        value: _topicPinned,
                        onChanged: topic == null
                            ? (_) {}
                            : (value) => unawaited(_setTopicPinned(value)),
                      ),
                      SettingsSwitchRow(
                        title: '消息免打扰',
                        value: _topicMuted,
                        onChanged: topic == null
                            ? (_) {}
                            : (value) => unawaited(_setTopicMuted(value)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (topic != null)
                    SettingsCard(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _exitTopic,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                '退出频道',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: const Color(0xFFFF3B30),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _memberStrip(AppColors c) {
    final people = _members.take(4).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        children: [
          for (final person in people) ...[
            Expanded(
              child: Column(
                children: [
                  PhotoAvatar(
                    title: person.name,
                    photo: person.photo,
                    size: 42,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    person.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
          Expanded(
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: c.searchFill,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(sfIcon('plus'), color: c.textSecondary),
                ),
                const SizedBox(height: 6),
                Text(
                  '邀请',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
