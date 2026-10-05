import 'package:flutter/material.dart';

class FitSegment<T> {
  final T value;
  final IconData? icon;
  final String label;
  const FitSegment(this.value, this.label, {this.icon});
}

/// SegmentedButton that never wraps labels mid-word on narrow phones:
/// icons are dropped when a segment gets too narrow and labels scale down
/// to one line instead of breaking ("Луч|ший").
class FitSegmented<T> extends StatelessWidget {
  final List<FitSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;
  const FitSegmented({super.key, required this.segments, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final per = box.maxWidth.isFinite ? box.maxWidth / segments.length : 200.0;
      // icon (18) + gap (8) + padding (~32) + label at ~8.5 px/char
      final longest = segments.fold<int>(0, (m, s) => s.label.length > m ? s.label.length : m);
      final icons = per >= longest * 8.5 + 64;
      return SizedBox(
        width: box.maxWidth.isFinite ? box.maxWidth : null,
        child: SegmentedButton<T>(
          showSelectedIcon: false,
          style: per < 104
              ? const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 6)))
              : null,
          segments: [
            for (final s in segments)
              ButtonSegment<T>(
                value: s.value,
                icon: icons && s.icon != null ? Icon(s.icon) : null,
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(s.label, maxLines: 1, softWrap: false),
                ),
              ),
          ],
          selected: {selected},
          onSelectionChanged: (v) => onChanged(v.first),
        ),
      );
    });
  }
}
