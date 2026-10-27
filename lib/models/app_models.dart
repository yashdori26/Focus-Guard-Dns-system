import 'package:flutter/material.dart';

class BlockedItem {
  final String id;
  final String name;
  final String icon;
  final Color color;
  final String? description;
  final List<String> packages;

  const BlockedItem({
    required this.id,
    required this.name,
    this.icon = '',
    this.color = Colors.blue,
    this.description,
    this.packages = const [],
  });
}

class QueryLog {
  final String id;
  final String subdomain;
  final String domain;
  final String time;
  final String icon;

  const QueryLog({
    required this.id,
    required this.subdomain,
    required this.domain,
    required this.time,
    required this.icon,
  });
}
