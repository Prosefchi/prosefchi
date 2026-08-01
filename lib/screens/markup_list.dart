import 'package:flutter/material.dart';

import '../models/markup.dart';
import 'markup_paragraph.dart';

/// A bulleted or numbered list, each marker beside its item.
///
/// Shared by the prayers screen and the welcome pages, which pass their own
/// style and spacing.
class MarkupItems extends StatelessWidget {
  const MarkupItems(this.list, {super.key, this.style});

  final MarkupList list;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    // The marker sits in a column of its own so the item text aligns down the
    // left however long the marker is. Scaled, because the text size setting
    // reaches this through the same MediaQuery the text is drawn from, and a
    // fixed width would crop "10." at the largest one.
    final width = MediaQuery.textScalerOf(context).scale(26);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, item) in list.items.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: width,
                  child: Text(
                    list.ordered ? '${index + 1}.' : '•',
                    style: style,
                  ),
                ),
                // Expanded, so a long item wraps rather than overflowing the
                // row. Greek runs longest and breaks first.
                Expanded(child: MarkupParagraph(item.spans, style: style)),
              ],
            ),
          ),
      ],
    );
  }
}
