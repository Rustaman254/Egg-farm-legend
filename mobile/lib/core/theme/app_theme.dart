import 'package:flutter/material.dart';

/// EggFarm Legends brand palette -- mirrors the webapp's dark "Pokedex-screen-at-night" theme
/// (see webapp/src/index.css) so the two clients read as the same game: Poke Ball red, sky
/// blue, electric yellow on a near-black ground, with the same rarity-tier "type" colors.
class AppColors {
  AppColors._();

  static const background = Color(0xFF12141C);
  static const cardSurface = Color(0xFF1C2030);
  static const surface2 = Color(0xFF262B3F);
  static const border = Color(0xFF383F57);

  static const textPrimary = Color(0xFFF0F2F8);
  static const textMuted = Color(0xFFA3ABC2);
  static const textFaint = Color(0xFF707A93);

  static const primary = Color(0xFFFF3B3B); // brand red -- primary CTAs
  static const primaryDark = Color(0xFFC40F0F); // brand red, dark -- pressed states, gradients
  static const secondary = Color(0xFF3DDC84); // "up" green -- success/positive
  static const accent = Color(0xFF4C80E6); // brand blue -- secondary actions
  static const gold = Color(0xFFFFCB05); // brand yellow -- rewards/highlights

  static const danger = Color(0xFFFF5C4D); // "down" red -- errors/losses
  static const warn = Color(0xFFFFB84D);
  static const rotten = Color(0xFF8D6E63);

  // Rarity tier "type" colors -- matches webapp/src/config/constants.ts RARITY_COLORS exactly
  // (the palette actually rendered by CreatureCard/EggCard/ListingCard etc.), which differs
  // slightly from the CSS theme's --color-rarity-* tokens that only back unused utility classes.
  static const rarityCommon = Color(0xFF9E9BA8);
  static const rarityUncommon = Color(0xFF35D07F);
  static const rarityRare = Color(0xFF38A1FF);
  static const rarityEpic = Color(0xFFB565F3);
  static const rarityLegendary = Color(0xFFFFB347);

  static Color forRarity(int rarity) {
    switch (rarity) {
      case 1:
        return rarityCommon;
      case 2:
        return rarityUncommon;
      case 3:
        return rarityRare;
      case 4:
        return rarityEpic;
      case 5:
        return rarityLegendary;
      default:
        return rarityCommon;
    }
  }
}

/// The webapp's "card-pop"/"card-pop-sm" flat sticker-shadow treatment (see
/// webapp/src/index.css): an offset, unblurred black shadow plus a thick rarity/status-colored
/// border, standing in for the TCG-card look used on every creature/egg/listing/task card.
BoxDecoration cardPopDecoration({
  required Color borderColor,
  double radius = 20,
  double borderWidth = 3,
  bool small = false,
  Color? fill,
}) {
  return BoxDecoration(
    color: fill ?? AppColors.cardSurface,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor, width: borderWidth),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: small ? 0.45 : 0.5),
        offset: small ? const Offset(3, 3) : const Offset(4, 4),
      ),
    ],
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: AppColors.primary,
        secondary: AppColors.accent,
        tertiary: AppColors.gold,
        surface: AppColors.cardSurface,
        error: AppColors.danger,
      ),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: AppColors.textPrimary,
            displayColor: AppColors.textPrimary,
          ),
    );

    return base.copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        centerTitle: false,
        elevation: 0,
        titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.3),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.surface2,
          disabledForegroundColor: AppColors.textFaint,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface2,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.accent, width: 2)),
        labelStyle: const TextStyle(color: AppColors.textMuted),
        hintStyle: const TextStyle(color: AppColors.textFaint),
      ),
      cardTheme: CardThemeData(
        color: AppColors.cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.border, width: 2)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(backgroundColor: AppColors.cardSurface),
      snackBarTheme: const SnackBarThemeData(backgroundColor: AppColors.surface2, contentTextStyle: TextStyle(color: AppColors.textPrimary)),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.cardSurface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textFaint,
        showUnselectedLabels: true,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.4),
        unselectedLabelStyle: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 0.4),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border),
      iconTheme: const IconThemeData(color: AppColors.textMuted),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
    );
  }
}
