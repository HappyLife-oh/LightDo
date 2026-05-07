import 'package:flutter/material.dart';

/// LightDo semantic color tokens.
///
/// Every color used across the app is defined here so themes (light/dark)
/// can swap the underlying values without touching widget code.
abstract final class AppColors {
  // ── Primary ──────────────────────────────────────────────────────────
  static const primary = Color(0xFF1D6F5F);
  static const primaryLight = Color(0xFF0D9488);
  static const onPrimary = Colors.white;

  // ── Scaffold / Background ────────────────────────────────────────────
  static const scaffoldBg = Color(0xFFF4F1E8);
  static const scaffoldBody = Color(0xFFF7F4ED);
  static const surfaceWhite = Colors.white;

  // ── Text ─────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFF1C2F2A);
  static const textSecondary = Color(0xFF173C35);
  static const textBody = Color(0xFF75817D);
  static const textBodyAlt = Color(0xFF78847F);
  static const textMuted = Color(0xFF70837E);
  static const textSettingsIcon = Color(0xFF4A5A55);

  // ── Badges ───────────────────────────────────────────────────────────
  static const badgeBg = Color(0xFFE8ECE4);
  static const badgeText = Color(0xFF4D5B56);

  // ── Composer ─────────────────────────────────────────────────────────
  static const composerIcon = Color(0xFF6C7A74);
  static const composerIconActive = Color(0xFF1D6F5F);
  static const composerDivider = Color(0xFFD9DED4);
  static const chipBg = Color(0xFFE9EFE8);
  static const chipText = Color(0xFF335049);

  // ── Section ──────────────────────────────────────────────────────────
  static const sectionBorder = Color(0xFFE2E5DD);
  static const completedTitle = Color(0xFF33413D);
  static const completedCount = Color(0xFF7A8580);

  // ── Empty state ──────────────────────────────────────────────────────
  static const emptyIconBg = Color(0xFFFFFFFF); // with 0.7 alpha
  static const emptyIcon = Color(0xFF2E6C60);
  static const emptyText = Color(0xFF6D827C);

  // ── Preview strip ────────────────────────────────────────────────────
  static const previewStripBg = Color(0xFFFFFFFF); // with 0.55 alpha
  static const previewCheckBg = Color(0xFFE5F0E8);
  static const previewCheckBorder = Color(0xFF94B39E);
  static const previewCheckIcon = Color(0xFF2E6C60);
  static const previewOverflowBg = Color(0xFFE9ECE7);
  static const previewOverflowText = Color(0xFF6C7A74);

  // ── Todo card – normal ───────────────────────────────────────────────
  static const cardNormalBorder = Color(0xFFE2E5DD);
  static const cardNormalTitle = Color(0xFF203B35);
  static const cardNormalSummary = Color(0xFF728781);
  static const cardCompletedTitle = Color(0xFF6F837D);

  // ── Todo card – overdue ──────────────────────────────────────────────
  static const cardOverdueBg = Color(0xFFFFF0EC);
  static const cardOverdueBorder = Color(0xFFE07A63);
  static const cardOverdueBadgeBg = Color(0xFFF7D2C8);
  static const cardOverdueBadgeText = Color(0xFFAC4C3A);
  static const cardOverdueTitle = Color(0xFF7E2F22);
  static const cardOverdueSummary = Color(0xFFB36456);

  // ── Todo card – dueSoon ──────────────────────────────────────────────
  static const cardDueSoonBg = Color(0xFFFFF8E5);
  static const cardDueSoonBorder = Color(0xFFD3A446);
  static const cardDueSoonBadgeBg = Color(0xFFF5E2B3);
  static const cardDueSoonBadgeText = Color(0xFF94691A);
  static const cardDueSoonTitle = Color(0xFF7D5D17);
  static const cardDueSoonSummary = Color(0xFF9B7626);

  // ── Error / warning ──────────────────────────────────────────────────
  static const errorBg = Color(0xFFFFF3E2);
  static const errorBorder = Color(0xFFFFD29A);
  static const errorIcon = Color(0xFFAF6700);

  // ── QR / Scan ────────────────────────────────────────────────────────
  static const scanErrorBg = Color(0xFFFFEBEE);
  static const scanErrorText = Color(0xFFC62828);

  // ── Sync ─────────────────────────────────────────────────────────────
  static const syncConnected = Color(0xFF2E6C60);
  static const syncWaiting = Color(0xFF9E9E9E);

  // ── Floating Ball ────────────────────────────────────────────────────
  static const ballNormalStart = Color(0xD91A7A68);
  static const ballNormalEnd = Color(0xD93CA692);
  static const ballOverdueStart = Color(0xFFE46048);
  static const ballOverdueEnd = Color(0xFFCC3A3A);
  static const ballCoveredStart = Color(0xFFD4AF4F);
  static const ballCoveredEnd = Color(0xFF91B64F);

  static const ballBorderNormal = Color(0xFFFFFFFF); // with 0.82 alpha
  static const ballBorderOverdue = Color(0xFFFFC2B8);
  static const ballBorderCovered = Color(0xFFF6E3A2);
  static const ballShadowColor = Color(0xFF1D6F5F); // with 0.18 alpha
  static const ballIconColor = Colors.white;

  // ── Dialog ───────────────────────────────────────────────────────────
  static const dialogHint = Color(0xFF6D827C);
}
