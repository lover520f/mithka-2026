//
//  main_tab_view.dart
//
//  Tab shell: 消息 / 联系人 / optional 动态, plus the left-sliding "我" profile drawer
//  overlaid above the tab bar. The bottom tab bar is either a custom flat bar
//  ("classic", default) or the system tab bar — chosen in 外观 settings. Port of
//  the Swift `MainTabView`.
//

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../call/call_manager.dart';
import '../call/call_screen.dart';
import '../chat/chat_view.dart';
import '../channels/topic_chat_view.dart';
import '../channels/topic_channels_view.dart';
import '../chats/chat_list_view.dart';
import '../components/drawer_controller.dart' as dc;
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../contacts/contacts_view.dart';
import '../moments/moments_view.dart';
import '../profile/profile_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import '../update/update_checker.dart';

/// Global unread badge source.
class UnreadBadgeModel extends ChangeNotifier {
  int _chatCount = 0;
  int _messageCount = 0;
  bool _started = false;

  int countFor(UnreadBadgeMode mode) => switch (mode) {
    UnreadBadgeMode.messages => _messageCount,
    UnreadBadgeMode.chats => _chatCount,
  };

  void start() {
    if (_started) return;
    _started = true;
    TdClient.shared.subscribe().listen((update) {
      switch (update.type) {
        case 'updateUnreadChatCount':
          if (update.obj('chat_list')?.type != 'chatListMain') return;
          _chatCount = update.integer('unread_unmuted_count') ?? 0;
          notifyListeners();
        case 'updateUnreadMessageCount':
          if (update.obj('chat_list')?.type != 'chatListMain') return;
          _messageCount = update.integer('unread_unmuted_count') ?? 0;
          notifyListeners();
      }
    });
  }
}

class MainTabView extends StatefulWidget {
  const MainTabView({super.key});

  @override
  State<MainTabView> createState() => _MainTabViewState();
}

class _MainTabViewState extends State<MainTabView> {
  int _selection = 0;
  late final dc.TabBarVisibility _tabBar = dc.TabBarVisibility();
  late final UnreadBadgeModel _unread = UnreadBadgeModel()..start();
  late final CallManager _calls = CallManager()..start();
  late final ChatListController _chatListController = ChatListController();
  ChatListSelection? _selectedMessageChat;

  @override
  void initState() {
    super.initState();
    // Android-only: check GitHub Releases for a newer same-ABI build (once).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateChecker.maybePrompt(context);
    });
  }

  @override
  void dispose() {
    _calls.dispose();
    _chatListController.dispose();
    super.dispose();
  }

  late final List<GlobalKey<NavigatorState>> _navKeys = List.generate(
    4,
    (_) => GlobalKey<NavigatorState>(),
  );

  static const _allTabs = [
    _MainTabItem(0, '消息', 'message.fill'),
    _MainTabItem(1, '频道', 'number.circle.fill'),
    _MainTabItem(2, '联系人', 'person.2.fill'),
    _MainTabItem(3, '动态', 'circle.dashed'),
  ];

  List<_MainTabItem> _visibleTabs(ThemeController theme) => [
    _allTabs[0],
    if (theme.showChannelsTab) _allTabs[1],
    _allTabs[2],
    if (theme.showMomentsTab) _allTabs[3],
  ];

  Widget _root(int i) => switch (i) {
    0 => ChatListView(controller: _chatListController),
    1 => const TopicChannelsView(),
    2 => const ContactsView(),
    _ => const MomentsView(),
  };

  Future<bool> _onWillPop() async {
    if (_selection == 0 &&
        _usesMessageSplit(context) &&
        _selectedMessageChat != null) {
      setState(() => _selectedMessageChat = null);
      return false;
    }
    final nav = _navKeys[_selection].currentState;
    if (nav != null && nav.canPop()) {
      nav.pop();
      return false;
    }
    return true;
  }

  void _select(int i) {
    final theme = context.read<ThemeController>();
    final tabs = _visibleTabs(theme);
    if (i < 0 || i >= tabs.length) return;
    final tabIndex = tabs[i].index;
    final shouldJumpUnread =
        tabIndex == 0 && _unread.countFor(theme.unreadBadgeMode) > 0;
    if (tabIndex == _selection) {
      // Tapping the active tab pops to its root.
      _navKeys[tabIndex].currentState?.popUntil((r) => r.isFirst);
      if (shouldJumpUnread) _scrollMessagesToFirstUnread();
      return;
    }
    setState(() => _selection = tabIndex);
    if (shouldJumpUnread) _scrollMessagesToFirstUnread();
  }

  void _scrollMessagesToFirstUnread() {
    _chatListController.scrollToFirstUnread();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _tabBar),
        ChangeNotifierProvider.value(value: _unread),
        ChangeNotifierProvider.value(value: _calls),
      ],
      // Material ancestor so the tab content (bare Containers) gets a proper
      // DefaultTextStyle instead of the debug red/yellow-underline fallback.
      child: Material(
        type: MaterialType.transparency,
        child: PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (!didPop) await _onWillPop();
          },
          child: Stack(
            children: [
              _classicTabs(),
              _drawerOverlay(),
              // Full-screen call HUD over everything when a call is active.
              Consumer<CallManager>(
                builder: (context, calls, _) => calls.call == null
                    ? const SizedBox.shrink()
                    : Positioned.fill(child: CallScreen(manager: calls)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - Per-tab navigators

  Widget _tabNavigator(int i) {
    return _TabNavigator(
      navigatorKey: _navKeys[i],
      observer: dc.TabDepthObserver(i, _tabBar),
      root: _root(i),
    );
  }

  int _visibleSelection(List<_MainTabItem> tabs) {
    final index = tabs.indexWhere((tab) => tab.index == _selection);
    return index < 0 ? tabs.length - 1 : index;
  }

  Widget _stack(List<_MainTabItem> tabs) => _LazyTabStack(
    selection: _visibleSelection(tabs),
    items: tabs,
    builder: (tab) => _tabNavigator(tab.index),
  );

  // MARK: - Classic (flat) tab bar

  Widget _classicTabs() {
    final theme = context.watch<ThemeController>();
    final tabs = _visibleTabs(theme);
    if (!tabs.any((tab) => tab.index == _selection)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selection = tabs.last.index);
      });
    }
    final selection = _visibleSelection(tabs);
    final activeTabIndex = tabs[selection].index;
    if (activeTabIndex == 0 && _usesMessageSplit(context)) {
      return _messageSplitTabs(tabs, selection);
    }
    return Column(
      children: [
        Expanded(child: _stack(tabs)),
        Consumer<dc.TabBarVisibility>(
          builder: (context, vis, _) {
            final hidden = vis.depth(activeTabIndex) > 0;
            return AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              child: hidden
                  ? const SizedBox(width: double.infinity)
                  : _ClassicTabBar(
                      selection: selection,
                      onSelect: _select,
                      items: tabs,
                      onClearUnread: _chatListController.markAllRead,
                      unread: context.watch<UnreadBadgeModel>().countFor(
                        theme.unreadBadgeMode,
                      ),
                    ),
            );
          },
        ),
      ],
    );
  }

  Widget _messageSplitTabs(List<_MainTabItem> tabs, int selection) {
    final theme = context.watch<ThemeController>();
    final size = MediaQuery.of(context).size;
    final sidebarWidth = (size.width * 0.32).clamp(320.0, 420.0).toDouble();
    return Row(
      children: [
        SizedBox(
          width: sidebarWidth,
          child: Column(
            children: [
              Expanded(
                child: ChatListView(
                  controller: _chatListController,
                  selectedChatId: _selectedMessageChat?.chatId,
                  onChatSelected: (chat) {
                    setState(() => _selectedMessageChat = chat);
                  },
                ),
              ),
              AnimatedBuilder(
                animation: _unread,
                builder: (context, _) => _ClassicTabBar(
                  selection: selection,
                  onSelect: _select,
                  items: tabs,
                  onClearUnread: _chatListController.markAllRead,
                  unread: _unread.countFor(theme.unreadBadgeMode),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _messageDetailPane()),
      ],
    );
  }

  Widget _messageDetailPane() {
    final selected = _selectedMessageChat;
    if (selected == null) return const _MessageEmptyPane();
    final chat = selected.chat;
    return KeyedSubtree(
      key: ValueKey('message-detail-${selected.chatId}-${selected.isForum}'),
      child: selected.isForum && chat != null
          ? TopicChatView(chat: chat, showBackButton: false)
          : ChatView(
              chatId: selected.chatId,
              title: selected.title,
              showBackButton: false,
            ),
    );
  }

  bool _usesMessageSplit(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return size.width > size.height && math.min(size.width, size.height) >= 600;
  }

  // MARK: - Drawer overlay (the "我" profile drawer)

  Widget _drawerOverlay() {
    return Consumer<dc.DrawerController>(
      builder: (context, drawer, _) {
        final width = math.min(MediaQuery.of(context).size.width * 0.88, 420.0);
        return IgnorePointer(
          ignoring: !drawer.isOpen,
          child: Stack(
            children: [
              AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                opacity: drawer.isOpen ? 1 : 0,
                child: GestureDetector(
                  onTap: drawer.close,
                  child: Container(color: Colors.black.withValues(alpha: 0.35)),
                ),
              ),
              AnimatedPositioned(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                left: drawer.isOpen ? 0 : -width,
                top: 0,
                bottom: 0,
                width: width,
                child: Material(
                  color: context.colors.groupedBackground,
                  child: const ProfileView(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MessageEmptyPane extends StatelessWidget {
  const _MessageEmptyPane();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Center(
        child: Opacity(
          opacity: 0.08,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset('assets/penguin.png', width: 92, height: 92),
              const SizedBox(width: 18),
              Text(
                'Mithka',
                style: TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w600,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MainTabItem {
  const _MainTabItem(this.index, this.label, this.icon);

  final int index;
  final String label;
  final String icon;
}

class _LazyTabStack extends StatefulWidget {
  const _LazyTabStack({
    required this.selection,
    required this.items,
    required this.builder,
  });

  final int selection;
  final List<_MainTabItem> items;
  final Widget Function(_MainTabItem tab) builder;

  @override
  State<_LazyTabStack> createState() => _LazyTabStackState();
}

class _LazyTabStackState extends State<_LazyTabStack> {
  final Set<int> _builtTabIndexes = {};

  @override
  void initState() {
    super.initState();
    _rememberSelection();
  }

  @override
  void didUpdateWidget(covariant _LazyTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    _builtTabIndexes.removeWhere(
      (index) => !widget.items.any((tab) => tab.index == index),
    );
    _rememberSelection();
  }

  void _rememberSelection() {
    if (widget.items.isEmpty) return;
    final selectedIndex = widget.selection
        .clamp(0, widget.items.length - 1)
        .toInt();
    final selected = widget.items[selectedIndex];
    _builtTabIndexes.add(selected.index);
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.selection,
      children: [
        for (final tab in widget.items)
          _builtTabIndexes.contains(tab.index)
              ? widget.builder(tab)
              : const SizedBox.expand(),
      ],
    );
  }
}

/// Hosts one tab's navigation stack so pushes stay within the tab.
class _TabNavigator extends StatelessWidget {
  const _TabNavigator({
    required this.navigatorKey,
    required this.observer,
    required this.root,
  });
  final GlobalKey<NavigatorState> navigatorKey;
  final NavigatorObserver observer;
  final Widget root;

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: navigatorKey,
      observers: [observer],
      onGenerateRoute: (settings) =>
          MaterialPageRoute(builder: (_) => root, settings: settings),
    );
  }
}

/// Flat bottom tab bar.
class _ClassicTabBar extends StatelessWidget {
  const _ClassicTabBar({
    required this.selection,
    required this.onSelect,
    required this.onClearUnread,
    required this.items,
    required this.unread,
  });
  final int selection;
  final ValueChanged<int> onSelect;
  final VoidCallback onClearUnread;
  final List<_MainTabItem> items;
  final int unread;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSelect(i),
                    child: Column(
                      mainAxisSize: MainAxisSize.max,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 28,
                          child: Stack(
                            clipBehavior: Clip.none,
                            alignment: Alignment.center,
                            children: [
                              Icon(
                                sfIcon(items[i].icon),
                                size: 26,
                                color: selection == i
                                    ? AppTheme.brand
                                    : c.textTertiary,
                              ),
                              if (i == 0 && unread > 0)
                                Positioned(
                                  right: -10,
                                  top: 0,
                                  child: UnreadBadge(
                                    count: unread,
                                    onClear: onClearUnread,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].label,
                          style: TextStyle(
                            fontSize: 11,
                            color: selection == i
                                ? AppTheme.brand
                                : c.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
