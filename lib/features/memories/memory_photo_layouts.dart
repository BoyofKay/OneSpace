import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:onespace/l10n/phrases.dart';

import 'memory_photo_layout_rules.dart';

/// Draws one photo at a height (the caller signs and loads it).
typedef MemoryPhotoBuilder = Widget Function(Map<String, dynamic> photo, double height);

/// R70: every memory photo layout in one place, used by the story editor
/// and the view screens. Stack and Slideshow can be swiped.
class MemoryPhotoLayout extends StatelessWidget {
  const MemoryPhotoLayout({super.key, required this.layout, required this.photos, required this.photo});
  final String layout;
  final List<Map<String, dynamic>> photos;
  final MemoryPhotoBuilder photo;

  String _caption(Map<String, dynamic> p) => (p['caption'] ?? '').toString();

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    switch (MemoryPhotoLayoutRules.safe(layout)) {
      case 'feature':
        return Column(children: [
          photo(photos.first, 245),
          if (photos.length > 1) const SizedBox(height: 6),
          if (photos.length > 1) SizedBox(height: 110, child: ListView.separated(
            scrollDirection: Axis.horizontal, itemCount: photos.length - 1,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (_, i) => SizedBox(width: 120, child: photo(photos[i + 1], 110)))),
        ]);
      case 'polaroid':
        return Wrap(spacing: 12, runSpacing: 12, alignment: WrapAlignment.center, children: [
          for (var i = 0; i < photos.length; i++) Transform.rotate(
            angle: (i.isEven ? -1 : 1) * math.pi / 72,
            child: SizedBox(width: 160, child: _Polaroid(child: photo(photos[i], 145), caption: _caption(photos[i])))),
        ]);
      case 'overlap':
        return _SwipeDeck(photos: photos, photo: photo);
      case 'carousel':
        return _Slideshow(photos: photos, photo: photo);
      case 'mosaic':
        return LayoutBuilder(builder: (ctx, box) {
          final w = box.maxWidth;
          return Column(children: [
            SizedBox(height: 250, child: Row(children: [
              Expanded(flex: 3, child: photo(photos.first, 250)),
              if (photos.length > 1) ...[
                const SizedBox(width: 6),
                Expanded(flex: 2, child: Column(children: [
                  Expanded(child: photo(photos[1], 122)),
                  if (photos.length > 2) ...[const SizedBox(height: 6), Expanded(child: photo(photos[2], 122))],
                ])),
              ],
            ])),
            if (photos.length > 3) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final p in photos.skip(3)) SizedBox(width: (w - 12) / 3, child: photo(p, 100)),
              ]),
            ],
          ]);
        });
      case 'film':
        return Container(
          decoration: BoxDecoration(color: const Color(0xFF1F1B1A), borderRadius: BorderRadius.circular(10)),
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(children: [
            const _Sprockets(),
            SizedBox(height: 150, child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              scrollDirection: Axis.horizontal, itemCount: photos.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => SizedBox(width: 200, child: photo(photos[i], 150)))),
            const _Sprockets(),
          ]));
      case 'scatter':
        return LayoutBuilder(builder: (ctx, box) {
          final w = box.maxWidth, card = math.min(170.0, w * .48);
          final rows = (photos.length / 2).ceil();
          return SizedBox(height: rows * (card * .92) + 40, child: Stack(children: [
            for (var i = 0; i < photos.length; i++) Positioned(
              left: i.isEven ? w * .03 + (i % 4 == 0 ? 0 : 12) : w - card - w * .03 - (i % 4 == 1 ? 10 : 0),
              top: (i ~/ 2) * (card * .9) + (i.isEven ? 0 : 22),
              width: card,
              child: Transform.rotate(angle: [-.08, .06, .04, -.05, .09, -.03][i % 6],
                child: _Polaroid(child: photo(photos[i], card * .82), caption: _caption(photos[i])))),
          ]));
        });
      case 'timeline':
        return Column(children: [
          for (var i = 0; i < photos.length; i++) IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(width: 28, child: Column(children: [
              Container(width: 12, height: 12, margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.primary)),
              if (i < photos.length - 1) Expanded(child: Container(width: 2, color: theme.colorScheme.primary.withValues(alpha: .35))),
            ])),
            Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                photo(photos[i], 190),
                if (_caption(photos[i]).isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5),
                  child: Text(tt(_caption(photos[i])), style: theme.textTheme.bodyMedium)),
              ]))),
          ])),
        ]);
      default:
        return LayoutBuilder(builder: (ctx, box) {
          final two = box.maxWidth >= 350;
          final width = two ? (box.maxWidth - 8) / 2 : box.maxWidth;
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in photos) SizedBox(width: width, child: photo(p, 175)),
          ]);
        });
    }
  }
}

class _Polaroid extends StatelessWidget {
  const _Polaroid({required this.child, this.caption = ''});
  final Widget child;
  final String caption;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.fromSTEB(6, 6, 6, 14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4),
      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(1, 4))]),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      child,
      if (caption.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 5),
        child: Text(tt(caption), maxLines: 2, overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF3B3533), fontSize: 12))),
    ]));
}

class _Sprockets extends StatelessWidget {
  const _Sprockets();
  @override
  Widget build(BuildContext context) => SizedBox(height: 12, child: LayoutBuilder(builder: (ctx, box) {
    final n = (box.maxWidth / 18).floor();
    return Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
      for (var i = 0; i < n; i++) Container(width: 8, height: 6,
        decoration: BoxDecoration(color: const Color(0xFFEDE6DF), borderRadius: BorderRadius.circular(1.5))),
    ]);
  }));
}

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count, index;
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (var i = 0; i < count; i++) AnimatedContainer(duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(horizontal: 3), width: i == index ? 16 : 7, height: 7,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(4),
          color: i == index ? c.primary : c.outlineVariant)),
    ]);
  }
}

/// Stack: the photos lie on top of each other; swipe left or right.
class _SwipeDeck extends StatefulWidget {
  const _SwipeDeck({required this.photos, required this.photo});
  final List<Map<String, dynamic>> photos;
  final MemoryPhotoBuilder photo;
  @override
  State<_SwipeDeck> createState() => _SwipeDeckState();
}

class _SwipeDeckState extends State<_SwipeDeck> {
  int index = 0;
  void go(int step) {
    final n = widget.photos.length;
    if (n < 2) return;
    setState(() => index = (index + step + n) % n);
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.photos.length;
    final i = index.clamp(0, n - 1);
    return Column(children: [
      GestureDetector(
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 50) return;
          final rtl = Directionality.of(context) == TextDirection.rtl;
          go((v < 0) != rtl ? 1 : -1);
        },
        child: SizedBox(height: 270, child: LayoutBuilder(builder: (ctx, box) {
          final w = math.min(260.0, box.maxWidth * .78);
          return Stack(alignment: Alignment.center, children: [
            for (var k = math.min(2, n - 1); k >= 1; k--) Transform.translate(
              offset: Offset(k * 10.0, k * 6.0),
              child: Transform.rotate(angle: k * .04, child: Opacity(opacity: .85,
                child: SizedBox(width: w, child: _Polaroid(child: widget.photo(widget.photos[(i + k) % n], 210)))))),
            AnimatedSwitcher(duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, a) => FadeTransition(opacity: a,
                child: ScaleTransition(scale: Tween(begin: .94, end: 1.0).animate(a), child: child)),
              child: SizedBox(key: ValueKey(i), width: w,
                child: _Polaroid(child: widget.photo(widget.photos[i], 210),
                  caption: (widget.photos[i]['caption'] ?? '').toString()))),
          ]);
        })),
      ),
      if (n > 1) ...[
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(tooltip: tt('Previous'), onPressed: () => go(-1), icon: const Icon(Icons.chevron_left)),
          _Dots(count: n, index: i),
          IconButton(tooltip: tt('Next'), onPressed: () => go(1), icon: const Icon(Icons.chevron_right)),
        ]),
        Text(tt('Swipe to see the next photo'), style: Theme.of(context).textTheme.bodySmall),
      ],
    ]);
  }
}

/// Slideshow: one big photo at a time, swipe through.
class _Slideshow extends StatefulWidget {
  const _Slideshow({required this.photos, required this.photo});
  final List<Map<String, dynamic>> photos;
  final MemoryPhotoBuilder photo;
  @override
  State<_Slideshow> createState() => _SlideshowState();
}

class _SlideshowState extends State<_Slideshow> {
  int index = 0;
  @override
  Widget build(BuildContext context) => Column(children: [
    SizedBox(height: 300, child: PageView.builder(
      itemCount: widget.photos.length,
      onPageChanged: (v) => setState(() => index = v),
      itemBuilder: (_, i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(children: [
          Expanded(child: widget.photo(widget.photos[i], 280)),
          if ((widget.photos[i]['caption'] ?? '').toString().isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(tt(widget.photos[i]['caption'].toString()), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ])))),
    if (widget.photos.length > 1) Padding(padding: const EdgeInsets.only(top: 8),
      child: _Dots(count: widget.photos.length, index: index)),
  ]);
}
