import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'theme/wabi_sabi_theme.dart';

Widget secCard(String title, String desc, {Widget? child, Widget? action}) {
  return Builder(
    builder: (context) {
      final palette = WabiSabiPalette.of(context);
      return Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: palette.ink,
                      letterSpacing: -0.25,
                    ),
                  ),
                ),
                if (action != null) action,
              ],
            ),
            if (desc.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                desc,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                  color: palette.mutedInk,
                  height: 1.45,
                ),
              ),
            ],
            if (child != null) ...[
              const SizedBox(height: 14),
              child,
            ],
          ],
        ),
      );
    },
  );
}

Widget switchRow(String title, String desc, bool value, ValueChanged<bool> onChanged) {
  return Builder(
    builder: (context) {
      final palette = WabiSabiPalette.of(context);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: palette.ink,
                      letterSpacing: -0.15,
                    ),
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      desc,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w400,
                        color: palette.mutedInk,
                        height: 1.35,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: palette.ink,
              activeTrackColor: palette.ink.withOpacity(0.35),
              inactiveThumbColor: palette.mutedInk,
              inactiveTrackColor: palette.border,
            ),
          ],
        ),
      );
    },
  );
}
