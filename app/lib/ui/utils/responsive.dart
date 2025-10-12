import 'package:flutter/material.dart';

class Breakpoints {
  static const double compact = 600;
  static const double medium = 900;
  static const double expanded = 1200;
}

bool isCompact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < Breakpoints.compact;
bool isMedium(BuildContext context) {
  final w = MediaQuery.sizeOf(context).width;
  return w >= Breakpoints.compact && w < Breakpoints.expanded;
}
bool isExpanded(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= Breakpoints.expanded;

