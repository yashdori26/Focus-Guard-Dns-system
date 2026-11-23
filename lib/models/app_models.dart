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

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'icon': icon,
    'color': color.value,
    'description': description,
    'packages': packages,
  };

  factory BlockedItem.fromJson(Map<String, dynamic> json) => BlockedItem(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    icon: json['icon'] as String? ?? '',
    color: Color(json['color'] as int? ?? 0xFF2563EB),
    description: json['description'] as String?,
    packages: (json['packages'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
  );
}

class QueryLog {
  final String id;
  final String subdomain;
  final String domain;
  final String time;
  final String icon;
  final bool isBlocked;

  const QueryLog({
    required this.id,
    required this.subdomain,
    required this.domain,
    required this.time,
    required this.icon,
    this.isBlocked = false,
  });
}

