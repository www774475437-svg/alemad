import 'dart:async';

import 'package:flutter/material.dart';

/// A row that slides by itself, one step every [every], and turns back at
/// its end. It waits while the reader is moving it by hand.
class AutoRow extends StatefulWidget {
  final double height;
  final double step;
  final double gap;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final Duration every;
  const AutoRow(
      {super.key,
      required this.height,
      required this.step,
      required this.gap,
      required this.itemCount,
      required this.itemBuilder,
      this.every = const Duration(seconds: 4)});

  @override
  State<AutoRow> createState() => _AutoRowState();
}

class _AutoRowState extends State<AutoRow> {
  final _scroll = ScrollController();
  Timer? _timer;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(widget.every, (_) {
      if (!mounted || !_scroll.hasClients) return;
      final p = _scroll.position;
      if (p.maxScrollExtent <= 0 || p.isScrollingNotifier.value) return;
      if (p.pixels >= p.maxScrollExtent - 4) _forward = false;
      if (p.pixels <= 4) _forward = true;
      final next = (p.pixels + (_forward ? widget.step : -widget.step)).clamp(0.0, p.maxScrollExtent);
      _scroll.animateTo(next, duration: const Duration(milliseconds: 700), curve: Curves.easeInOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: widget.height,
        child: ListView.separated(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: widget.itemCount,
          separatorBuilder: (context, i) => SizedBox(width: widget.gap),
          itemBuilder: widget.itemBuilder,
        ),
      );
}
