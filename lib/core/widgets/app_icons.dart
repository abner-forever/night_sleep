import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The prototype's custom 24×24 icon set, transcribed verbatim from
/// `src/icons.tsx`.
///
/// Every glyph is defined as the exact SVG path data shipped with the design
/// rather than approximated with a lookalike Material icon — several of these
/// (the snore profile, the ocean band, the sleep moon) have no close system
/// equivalent, and substituting one would visibly change the design.
///
/// The prototype's `I` wrapper draws with `fill: none`, `stroke: currentColor`,
/// round caps and joins; [glyph] reproduces that, substituting the requested
/// colour for `currentColor` because flutter_svg does not resolve it.
class AppIcons {
  const AppIcons._();

  static const _moon =
      '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/>';
  static const _pen =
      '<path d="M12 20h9"/><path d="M16.5 3.5a2.12 2.12 0 0 1 3 3L7 19l-4 1 1-4Z"/>';
  static const _chart = '<path d="M3 3v18h18"/><path d="M7 16l4-4 4 4 4-4"/>';
  static const _gear =
      '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83-2.83l.06-.06A1.65 1.65 0 0 0 4.68 15a1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 2.83-2.83l.06.06A1.65 1.65 0 0 0 9 4.68a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 2.83l-.06.06A1.65 1.65 0 0 0 19.4 9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>';
  static const _music =
      '<path d="M9 18V5l12-2v13"/><circle cx="6" cy="18" r="3"/><circle cx="18" cy="16" r="3"/>';
  static const _chevronDown = '<polyline points="6 9 12 15 18 9"/>';
  static const _chevronRight = '<polyline points="9 18 15 12 9 6"/>';
  static const _chevronUp = '<polyline points="18 15 12 9 6 15"/>';
  static const _play = '<polygon points="5 3 19 12 5 21 5 3"/>';
  static const _stop = '<rect x="3" y="3" width="18" height="18" rx="2"/>';
  static const _star =
      '<polygon points="12 2 15.09 8.26 22 9.27 17 14.14 18.18 21.02 12 17.77 5.82 21.02 7 14.14 2 9.27 8.91 8.26 12 2"/>';
  static const _wave =
      '<path d="M2 12c1.5-3 3-4.5 4.5-4.5S9 9 10.5 12s3 4.5 4.5 4.5S18 15 19.5 12 21 7.5 22 6"/>';
  static const _bed =
      '<path d="M2 4v16"/><path d="M2 8h18a2 2 0 0 1 2 2v10"/><path d="M2 17h20"/><path d="M6 8v9"/>';
  static const _sun =
      '<circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/>';
  static const _snore =
      '<path d="M9 17H5a2 2 0 0 0-2 2"/><path d="M12 17v2"/><path d="M9 12H5a2 2 0 0 0-2 2v1"/><path d="M12 12v3"/><path d="M9 7H7a2 2 0 0 0-2 2v1"/><path d="M12 7v3"/><circle cx="17" cy="12" r="5"/><path d="M14 10h6l-6 4h6"/>';
  static const _bubble =
      '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>';
  static const _sparkle =
      '<path d="m12 3-1.9 5.8a2 2 0 0 1-1.287 1.288L3 12l5.813 1.9a2 2 0 0 1 1.288 1.287L12 21l1.9-5.813a2 2 0 0 1 1.287-1.287L21 12l-5.813-1.9a2 2 0 0 1-1.288-1.288Z"/>';
  static const _clock =
      '<circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/>';
  static const _check = '<polyline points="20 6 9 17 4 12"/>';
  static const _sleep =
      '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/><path d="M9 9h3l-3 3h3"/><path d="M14 7h2l-2 2h2"/>';
  static const _volume =
      '<polygon points="11 5 6 9 2 9 2 15 6 15 11 19 11 5"/><path d="M19.07 4.93a10 10 0 0 1 0 14.14"/><path d="M15.54 8.46a5 5 0 0 1 0 7.07"/>';
  static const _timer =
      '<circle cx="12" cy="13" r="8"/><path d="M12 9v4l2 2"/><path d="M5 3 2 6"/><path d="m22 6-3-3"/><path d="M6.38 18.7 4 21"/><path d="M17.64 18.67 20 21"/>';
  static const _ai =
      '<path d="m12 3-1.9 5.8a2 2 0 0 1-1.287 1.288L3 12l5.813 1.9a2 2 0 0 1 1.288 1.287L12 21l1.9-5.813a2 2 0 0 1 1.287-1.287L21 12l-5.813-1.9a2 2 0 0 1-1.288-1.288Z"/><circle cx="12" cy="12" r="2" fill="currentColor" stroke="none"/>';
  static const _forest =
      '<path d="M12 2 7 9h10z"/><path d="M8 9 4 16h8z"/><path d="M16 9l-4 7h8z"/><rect x="10" y="16" width="4" height="6"/>';
  static const _fire =
      '<path d="M8.5 14.5A2.5 2.5 0 0 0 11 12c0-1.38-.5-2-1-3-1.072-2.143-.224-4.054 2-6 .5 2.5 2 4.9 4 6.5 2 1.6 3 3.5 3 5.5a7 7 0 1 1-14 0c0-1.153.433-2.294 1-3a2.5 2.5 0 0 0 2.5 2.5z"/>';
  static const _ocean =
      '<path d="M2 6c.6.5 1.2 1 2.5 1C7 7 7 5 9.5 5c2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/><path d="M2 12c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/><path d="M2 18c.6.5 1.2 1 2.5 1 2.5 0 2.5-2 5-2 2.6 0 2.4 2 5 2 2.5 0 2.5-2 5-2 1.3 0 1.9.5 2.5 1"/>';
  static const _rain =
      '<path d="M20 17.58A5 5 0 0 0 18 8h-1.26A8 8 0 1 0 4 16.25"/><line x1="8" y1="19" x2="8" y2="21"/><line x1="8" y1="13" x2="8" y2="15"/><line x1="16" y1="19" x2="16" y2="21"/><line x1="16" y1="13" x2="16" y2="15"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="12" y1="15" x2="12" y2="17"/>';
  static const _fan =
      '<path d="M12 12a3 3 0 1 0 0-6 3 3 0 0 0 0 6z"/><path d="M12 6V2"/><path d="M16.24 7.76l2.83-2.83"/><path d="M18 12h4"/><path d="M16.24 16.24l2.83 2.83"/><path d="M12 18v4"/><path d="M7.76 16.24l-2.83 2.83"/><path d="M6 12H2"/><path d="M7.76 7.76 4.93 4.93"/>';

  // Filled glyphs the prototype swaps in for the active tab. Only three tabs
  // have a filled counterpart; Settings falls back to the stroked icon.
  static const _moonFilled =
      '<path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z" fill="currentColor" stroke="none"/>';
  static const _penFilled =
      '<path d="M3 17.25V21h3.75L17.81 9.94l-3.75-3.75L3 17.25ZM20.71 7.04a1 1 0 0 0 0-1.41l-2.34-2.34a1 1 0 0 0-1.41 0l-1.83 1.83 3.75 3.75 1.83-1.83Z" fill="currentColor" stroke="none"/>';
  static const _chartFilled =
      '<rect x="3" y="12" width="3.8" height="8" rx="1.9" fill="currentColor" stroke="none"/><rect x="10.1" y="7" width="3.8" height="13" rx="1.9" fill="currentColor" stroke="none"/><rect x="17.2" y="3" width="3.8" height="17" rx="1.9" fill="currentColor" stroke="none"/>';

  static String _hex(Color color) {
    final value = color.toARGB32();
    final rgb = value & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0')}';
  }

  /// Renders [body] inside the prototype's stroked 24×24 frame.
  static Widget glyph(
    String body, {
    double size = 24,
    Color? color,
    double strokeWidth = 1.6,
    String? semanticLabel,
  }) {
    final paint = _hex(color ?? const Color(0xFF000000));
    // `currentColor` is substituted textually: flutter_svg leaves the literal
    // token unresolved, which would paint these fills black in dark mode.
    final resolved = body.replaceAll('currentColor', paint);
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" '
        'stroke="$paint" stroke-width="$strokeWidth" stroke-linecap="round" '
        'stroke-linejoin="round">$resolved</svg>';

    final picture = SvgPicture.string(
      svg,
      width: size,
      height: size,
      // Exclude from semantics by default; callers that need a label wrap the
      // icon in a labelled control, matching the prototype's aria handling.
      excludeFromSemantics: semanticLabel == null,
      semanticsLabel: semanticLabel,
    );
    return picture;
  }

  static Widget moon(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_moon, size: size, color: color, strokeWidth: strokeWidth);

  static Widget pen(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_pen, size: size, color: color, strokeWidth: strokeWidth);

  static Widget chart(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_chart, size: size, color: color, strokeWidth: strokeWidth);

  static Widget gear(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_gear, size: size, color: color, strokeWidth: strokeWidth);

  static Widget music(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_music, size: size, color: color, strokeWidth: strokeWidth);

  static Widget chevronDown(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_chevronDown, size: size, color: color, strokeWidth: strokeWidth);

  static Widget chevronRight(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_chevronRight, size: size, color: color, strokeWidth: strokeWidth);

  static Widget chevronUp(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_chevronUp, size: size, color: color, strokeWidth: strokeWidth);

  static Widget play(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_play, size: size, color: color, strokeWidth: strokeWidth);

  static Widget stop(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_stop, size: size, color: color, strokeWidth: strokeWidth);

  static Widget star(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_star, size: size, color: color, strokeWidth: strokeWidth);

  static Widget wave(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_wave, size: size, color: color, strokeWidth: strokeWidth);

  static Widget bed(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_bed, size: size, color: color, strokeWidth: strokeWidth);

  static Widget sun(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_sun, size: size, color: color, strokeWidth: strokeWidth);

  static Widget snore(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_snore, size: size, color: color, strokeWidth: strokeWidth);

  static Widget bubble(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_bubble, size: size, color: color, strokeWidth: strokeWidth);

  static Widget sparkle(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_sparkle, size: size, color: color, strokeWidth: strokeWidth);

  static Widget clock(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_clock, size: size, color: color, strokeWidth: strokeWidth);

  static Widget check(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_check, size: size, color: color, strokeWidth: strokeWidth);

  static Widget sleep(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_sleep, size: size, color: color, strokeWidth: strokeWidth);

  static Widget volume(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_volume, size: size, color: color, strokeWidth: strokeWidth);

  static Widget timer(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_timer, size: size, color: color, strokeWidth: strokeWidth);

  static Widget ai(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_ai, size: size, color: color, strokeWidth: strokeWidth);

  static Widget forest(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_forest, size: size, color: color, strokeWidth: strokeWidth);

  static Widget fire(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_fire, size: size, color: color, strokeWidth: strokeWidth);

  static Widget ocean(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_ocean, size: size, color: color, strokeWidth: strokeWidth);

  static Widget rain(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_rain, size: size, color: color, strokeWidth: strokeWidth);

  static Widget fan(
          {double size = 24, Color? color, double strokeWidth = 1.6}) =>
      glyph(_fan, size: size, color: color, strokeWidth: strokeWidth);

  /// Filled tab glyph for [id]; returns null when the design has no filled
  /// variant, and the caller falls back to the stroked icon.
  static Widget? filledTabGlyph(
    String id, {
    double size = 21,
    Color? color,
  }) {
    final body = switch (id) {
      'home' => _moonFilled,
      'log' => _penFilled,
      'stats' => _chartFilled,
      _ => null,
    };
    if (body == null) return null;
    return glyph(body, size: size, color: color, strokeWidth: 0);
  }
}
