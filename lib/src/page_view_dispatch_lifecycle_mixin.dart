import 'package:extended_tabs/extended_tabs.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'lifecycle_aware.dart';

/// Dispatches lifecycle events to child page.
mixin PageViewDispatchLifecycleMixin<T extends StatefulWidget>
    on State<T>, LifecycleAware {
  PageController? _pageController;

  /// Current page.
  int _curPage = 0;

  /// Map of page index and child.
  final Map<int, LifecycleAware> _lifecycleSubscribers = {};

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // visitChildElements() can not be called during build, so we schedule a frame callback.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _updateController();
    });
  }

  @override
  void dispose() {
    _pageController?.removeListener(_onPageChanged);
    super.dispose();
  }

  bool get _isBuilding =>
      SchedulerBinding.instance.schedulerPhase ==
      SchedulerPhase.persistentCallbacks;

  void _doSubscribe(int index, LifecycleAware lifecycleAware) {
    if (_lifecycleSubscribers[index] != lifecycleAware) {
      _lifecycleSubscribers[index] = lifecycleAware;
      // Dispatch [LifecycleEvent.active] to initial page.
      if (_curPage == index) {
        if (ModalRoute.of(context)!.isCurrent) {
          dispatchEvents(lifecycleEventsVisibleAndActive);
        } else {
          dispatchEvents([LifecycleEvent.visible]);
        }
      }
    }
  }

  void subscribe(int index, LifecycleAware lifecycleAware) {
    if (_pageController == null) {
      if (_isBuilding) {
        // If the widget is building, we need to wait for the next frame to
        // find controller and subscribe to the lifecycle event.
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (_pageController == null) {
            _updateController();
          }
          _doSubscribe(index, lifecycleAware);
        });
      } else {
        // Will never be reached?
        _updateController();
        _doSubscribe(index, lifecycleAware);
      }
    } else {
      _doSubscribe(index, lifecycleAware);
    }
  }

  void unsubscribe(LifecycleAware lifecycleAware) {
    if (_lifecycleSubscribers.containsValue(lifecycleAware)) {
      _lifecycleSubscribers
          .removeWhere((key, value) => value == lifecycleAware);
    }
  }

  @override
  void handleLifecycleEvents(List<LifecycleEvent> events) {
    super.handleLifecycleEvents(events);
    dispatchEvents(events);
  }

  /// Dispatch [events] to subscribers.
  void dispatchEvents(List<LifecycleEvent> events) {
    _lifecycleSubscribers[_curPage]?.handleLifecycleEvents(events);
  }

  /// Find and update [PageController]。
  void _updateController() {
    if (!mounted) return;

    PageController? pageController;

    // [TabBarView]内部实现也是嵌套PageView，所以这里查找PageView就可以了
    void findPageView(Element element) {
      if (element.widget is PageView) {
        PageView pageView = element.widget as PageView;
        pageController = pageView.controller;
        return;
      }
      if (element.widget is ExtendedPageView) {
        ExtendedPageView pageView = element.widget as ExtendedPageView;
        pageController = pageView.controller;
        return;
      }

      element.visitChildren(findPageView);
    }

    context.visitChildElements(findPageView);
    if (pageController == null) {
      throw FlutterError('Child widget is not a PageView nor a TabBarView.');
    }

    PageController newValue = pageController!;
    if (_pageController == newValue) return;
    final ScrollController? oldValue = _pageController;
    _pageController = newValue;
    if (_pageController!.hasClients) {
      _curPage = _pageController!.page?.round() ?? _pageController!.initialPage;
    } else {
      _curPage = _pageController!.initialPage;
    }
    oldValue?.removeListener(_onPageChanged);
    newValue.addListener(_onPageChanged);
  }

  void _onPageChanged() {
    if (_pageController!.page == null) return;
    int page = _pageController!.page!.round();
    if (_curPage == page) return;
    // print('PageController#onPageChanged: from page[$curPage]');
    dispatchEvents(lifecycleEventsInactiveAndInvisible);
    _curPage = page;
    // print('PageController#onPageChanged: to page[$curPage]');
    if (ModalRoute.of(context)?.isCurrent == true) {
      dispatchEvents(lifecycleEventsVisibleAndActive);
    } else {
      dispatchEvents([LifecycleEvent.visible]);
    }
  }
}
