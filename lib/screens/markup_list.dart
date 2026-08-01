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
    // The marker sits in a column of its own, so a wrapped item hangs under its
    // own text. Scaled: a fixed width crops "10." at the largest text size.
    final width = MediaQuery.textScalerOf(context).scale(26);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 6,
      children: [
        for (final (index, item) in list.items.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: width,
                child: Text(list.ordered ? '${index + 1}.' : '•', style: style),
              ),
              Expanded(child: MarkupParagraph(item.spans, style: style)),
            ],
          ),
      ],
    );
  }
}
