import 'package:flutter/material.dart';
import '../theme/wabi_sabi_theme.dart';

/// Rich International Country Picker with Continental Tabs and Search
class CountryPickerDialog extends StatefulWidget {
  final List<Map<String, dynamic>> countries;
  final WabiSabiPalette palette;
  final Function(String code, String dial, String flag) onSelected;

  const CountryPickerDialog({
    super.key,
    required this.countries,
    required this.palette,
    required this.onSelected,
  });

  static void show(
    BuildContext context, {
    required List<Map<String, dynamic>> countries,
    required WabiSabiPalette palette,
    required Function(String code, String dial, String flag) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => CountryPickerDialog(
        countries: countries,
        palette: palette,
        onSelected: onSelected,
      ),
    );
  }

  @override
  State<CountryPickerDialog> createState() => _CountryPickerDialogState();
}

class _CountryPickerDialogState extends State<CountryPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedContinent = 'All';
  List<Map<String, dynamic>> _filtered = [];

  final List<String> _continents = [
    'All',
    'Asia',
    'Americas',
    'Europe',
    'Middle East',
    'Africa',
    'Oceania',
  ];

  static const Map<String, List<String>> _continentCodes = {
    'Asia': ['IN', 'CN', 'JP', 'KR', 'SG', 'MY', 'ID', 'TH', 'VN', 'PH', 'BD', 'PK', 'LK', 'HK', 'TW'],
    'Americas': ['US', 'CA', 'MX', 'BR', 'AR', 'CO', 'CL', 'PE', 'PA', 'CR', 'JM', 'DO', 'TT', 'UY'],
    'Europe': ['GB', 'DE', 'FR', 'NL', 'IT', 'ES', 'CH', 'SE', 'NO', 'DK', 'FI', 'IE', 'PL', 'AT', 'BE', 'CZ', 'PT', 'GR', 'UA', 'RO', 'HU'],
    'Middle East': ['AE', 'SA', 'IL', 'QA', 'KW', 'BH', 'OM', 'JO', 'LB', 'TR', 'IR', 'IQ'],
    'Africa': ['ZA', 'NG', 'EG', 'KE', 'MA', 'GH', 'ET', 'DZ', 'AO', 'UG', 'TN'],
    'Oceania': ['AU', 'NZ', 'FJ', 'PG'],
  };

  @override
  void initState() {
    super.initState();
    _filtered = widget.countries;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      _filtered = widget.countries.where((c) {
        final code = (c['country_code'] ?? '').toString().toUpperCase();
        final name = (c['country_name'] ?? '').toString().toLowerCase();
        final dial = (c['dial_code'] ?? '').toString().toLowerCase();

        // Check continent
        if (_selectedContinent != 'All') {
          final allowedCodes = _continentCodes[_selectedContinent] ?? [];
          if (!allowedCodes.contains(code)) return false;
        }

        // Check search query
        if (q.isNotEmpty) {
          return name.contains(q) || code.toLowerCase().contains(q) || dial.contains(q);
        }
        return true;
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      child: Column(
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 38,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Select Country & Dial Code',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: palette.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_filtered.length} regions available with instant SMS',
                    style: TextStyle(fontSize: 12, color: palette.mutedInk),
                  ),
                ],
              ),
              IconButton(
                icon: Icon(Icons.close, color: palette.mutedInk, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Search Field
          TextField(
            controller: _searchController,
            onChanged: (_) => _applyFilters(),
            style: TextStyle(fontSize: 13, color: palette.ink),
            decoration: InputDecoration(
              hintText: 'Search by country, code, or dial code (+91, India)...',
              hintStyle: TextStyle(fontSize: 13, color: palette.mutedInk),
              prefixIcon: Icon(Icons.search, size: 18, color: palette.mutedInk),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, size: 16, color: palette.mutedInk),
                      onPressed: () {
                        _searchController.clear();
                        _applyFilters();
                      },
                    )
                  : null,
              filled: true,
              fillColor: palette.canvas,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.ink, width: 1.5),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Continental Filter Chips Bar
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _continents.map((continent) {
                final isSelected = (_selectedContinent == continent);
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(continent),
                    selected: isSelected,
                    onSelected: (val) {
                      setState(() => _selectedContinent = continent);
                      _applyFilters();
                    },
                    selectedColor: palette.ink,
                    backgroundColor: palette.canvas,
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? palette.canvas : palette.ink,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? palette.ink : palette.border,
                      ),
                    ),
                    showCheckmark: false,
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 12),

          // Country List
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.public_off, size: 36, color: palette.mutedInk.withOpacity(0.5)),
                        const SizedBox(height: 8),
                        Text(
                          'No country matches your search',
                          style: TextStyle(fontSize: 13, color: palette.mutedInk),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => Divider(height: 1, color: palette.border.withOpacity(0.6)),
                    itemBuilder: (ctx, i) {
                      final item = _filtered[i];
                      final code = item['country_code']?.toString() ?? '';
                      final name = item['country_name']?.toString() ?? code;
                      final dial = item['dial_code']?.toString() ?? '';
                      final flag = item['flag']?.toString() ?? '🌐';

                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        leading: Text(flag, style: const TextStyle(fontSize: 24)),
                        title: Text(
                          name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: palette.ink,
                          ),
                        ),
                        subtitle: Text(
                          'ISO: $code',
                          style: TextStyle(fontSize: 11, color: palette.mutedInk),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: palette.ink.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            dial,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: palette.ink,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        ),
                        onTap: () {
                          widget.onSelected(code, dial, flag);
                          Navigator.pop(ctx);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
