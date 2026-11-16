import 'package:flutter/material.dart';

class DeviceGrid extends StatelessWidget {
  const DeviceGrid({super.key, required this.children});
  final List<Widget> children;

  // Use two comfortably sized control columns on wide panels and one on phones.
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 760 ? 2 : 1;
      final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 8,
        children: [for (final child in children) SizedBox(key: child.key, width: width, child: child)],
      );
    },
  );
}
