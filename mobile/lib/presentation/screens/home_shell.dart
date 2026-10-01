import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/activity/activity_cubit.dart';
import '../../blocs/auth/auth_cubit.dart';
import '../../blocs/battle/battle_cubit.dart';
import '../../blocs/breeding/breeding_cubit.dart';
import '../../blocs/dex/dex_cubit.dart';
import '../../blocs/farm/farm_bloc.dart';
import '../../blocs/leaderboard/leaderboard_cubit.dart';
import '../../blocs/marketplace/marketplace_bloc.dart';
import '../../blocs/task/task_bloc.dart';
import '../../core/constants/app_constants.dart';
import '../../core/di/injector.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/battle.dart';
import '../../data/repositories/task_repository.dart';
import 'activity_screen.dart';
import 'battle_arena_screen.dart';
import 'breeding_lab_screen.dart';
import 'collection_screen.dart';
import 'farm_screen.dart';
import 'inventory_screen.dart';
import 'leaderboard_screen.dart';
import 'marketplace_screen.dart';
import 'task_board_screen.dart';

String _shortAddress(String address) => '${address.substring(0, 6)}...${address.substring(address.length - 4)}';

// Screen indices into the shared IndexedStack (see _HomeShellState.build). The bottom nav only
// surfaces 4 of these directly; the rest live behind the "More" sheet so the bar doesn't get
// cramped with 9 tiny icons.
const _iFarm = 0;
const _iTasks = 1;
const _iBreed = 2;
const _iBattle = 3;
const _iMarket = 4;
const _iInventory = 5;
const _iCollection = 6;
const _iLeaderboard = 7;
const _iActivity = 8;

class _MoreDestination {
  final int index;
  final IconData icon;
  final String label;
  const _MoreDestination({required this.index, required this.icon, required this.label});
}

const _moreDestinations = [
  _MoreDestination(index: _iMarket, icon: Icons.storefront, label: 'Marketplace'),
  _MoreDestination(index: _iBreed, icon: Icons.science, label: 'Breeding Lab'),
  _MoreDestination(index: _iInventory, icon: Icons.inventory_2, label: 'Inventory'),
  _MoreDestination(index: _iCollection, icon: Icons.menu_book, label: 'Species Dex'),
  _MoreDestination(index: _iLeaderboard, icon: Icons.emoji_events, label: 'Leaderboard'),
  _MoreDestination(index: _iActivity, icon: Icons.history, label: 'Activity'),
];

/// Bottom-nav shell hosting all 9 screens. Each tab's BLoC is provided here (not per-screen) so
/// switching tabs doesn't lose in-flight state (e.g. a pending "Feeding..." banner survives a
/// tab switch back to Farm).
///
/// Only 4 destinations are pinned to the bottom bar (Farm, Tasks, Battle, plus a "More" sheet);
/// the remaining screens (Marketplace, Breeding Lab, Inventory, Species Dex, Leaderboard,
/// Activity) open from that sheet instead of crowding the bar with 9 tiny icons.
class HomeShell extends StatefulWidget {
  final String wallet;
  const HomeShell({super.key, required this.wallet});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = _iFarm;

  @override
  void initState() {
    super.initState();
    // Fire-and-forget: records the daily-login streak and completes the daily_login task.
    getIt<TaskRepository>().recordLogin(widget.wallet);
  }

  // The bottom bar's own index is a separate 0..3 space from `_index` (0..8): the first 3 slots
  // map 1:1 to Farm/Tasks/Battle, and the 4th ("More") just opens a sheet rather than selecting
  // a screen -- so it stays highlighted whenever the active screen is one of the "More" ones.
  int get _navBarIndex {
    switch (_index) {
      case _iFarm:
        return 0;
      case _iTasks:
        return 1;
      case _iBattle:
        return 2;
      default:
        return 3;
    }
  }

  void _onNavTap(int navIndex) {
    switch (navIndex) {
      case 0:
        setState(() => _index = _iFarm);
      case 1:
        setState(() => _index = _iTasks);
      case 2:
        setState(() => _index = _iBattle);
      default:
        _showMoreSheet(context);
    }
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 12),
                child: Text('More', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.95,
                children: [
                  for (final dest in _moreDestinations)
                    _MoreTile(
                      destination: dest,
                      selected: _index == dest.index,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        setState(() => _index = dest.index);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (_) => FarmBloc(getIt())),
        BlocProvider(create: (_) => TaskBloc(getIt())),
        BlocProvider(create: (_) => MarketplaceBloc(getIt())),
        BlocProvider(create: (_) => BreedingCubit(getIt())),
        BlocProvider(create: (_) => BattleCubit(repository: getIt(), wallet: widget.wallet)),
        BlocProvider(create: (_) => DexCubit(getIt())),
        BlocProvider(create: (_) => LeaderboardCubit(getIt())),
        BlocProvider(create: (_) => ActivityCubit(getIt())),
      ],
      child: Builder(builder: (context) {
        final screens = [
          FarmScreen(wallet: widget.wallet),
          TaskBoardScreen(wallet: widget.wallet),
          BreedingLabScreen(wallet: widget.wallet),
          BattleArenaScreen(wallet: widget.wallet),
          MarketplaceScreen(wallet: widget.wallet),
          InventoryScreen(wallet: widget.wallet),
          CollectionScreen(wallet: widget.wallet),
          LeaderboardScreen(wallet: widget.wallet),
          ActivityScreen(wallet: widget.wallet),
        ];

        return Scaffold(
          body: Stack(
            children: [
              IndexedStack(index: _index, children: screens),
              _GlobalChallengeBanner(onOpenBattle: () => setState(() => _index = _iBattle)),
              _AccountChip(wallet: widget.wallet),
            ],
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: _navBarIndex,
            onTap: _onNavTap,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(icon: Icon(Icons.agriculture), label: 'FARM'),
              BottomNavigationBarItem(icon: Icon(Icons.checklist), label: 'TASKS'),
              BottomNavigationBarItem(icon: Icon(Icons.sports_kabaddi), label: 'BATTLE'),
              BottomNavigationBarItem(icon: Icon(Icons.grid_view), label: 'MORE'),
            ],
          ),
        );
      }),
    );
  }
}

class _MoreTile extends StatelessWidget {
  final _MoreDestination destination;
  final bool selected;
  final VoidCallback onTap;
  const _MoreTile({required this.destination, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        decoration: cardPopDecoration(
          borderColor: selected ? AppColors.primary : AppColors.border,
          radius: 16,
          borderWidth: selected ? 2.5 : 1.5,
          small: true,
          fill: selected ? AppColors.primary.withValues(alpha: 0.15) : AppColors.surface2,
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(destination.icon, color: selected ? AppColors.primary : AppColors.textMuted),
            const SizedBox(height: 8),
            Text(
              destination.label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: selected ? AppColors.primary : AppColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small top-right chip showing the (truncated) wallet address -- tapping it opens the account
/// sheet with the full address and a Log Out action. The only account-management entry point in
/// the shell, since each tab's own Scaffold/AppBar doesn't have a shared slot for it.
class _AccountChip extends StatelessWidget {
  final String wallet;
  const _AccountChip({required this.wallet});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      right: 12,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showAccountSheet(context, wallet),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.cardSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.account_circle, size: 16, color: AppColors.textMuted),
                const SizedBox(width: 4),
                Text(_shortAddress(wallet), style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showAccountSheet(BuildContext context, String wallet) {
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Your Wallet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 6),
            SelectableText(wallet, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () {
                Navigator.of(sheetContext).pop();
                context.read<AuthCubit>().logout();
              },
              child: const Text('Log Out'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Shows "Player X wants to fight you!" over whichever tab is currently open (not just the
/// Battle tab) and plays a system alert sound the moment a new incoming challenge appears --
/// BattleCubit already polls/pushes for these app-wide, this just surfaces it globally instead of
/// leaving it buried inside the Battle tab.
class _GlobalChallengeBanner extends StatefulWidget {
  final VoidCallback onOpenBattle;
  const _GlobalChallengeBanner({required this.onOpenBattle});

  @override
  State<_GlobalChallengeBanner> createState() => _GlobalChallengeBannerState();
}

class _GlobalChallengeBannerState extends State<_GlobalChallengeBanner> {
  int? _lastAnnouncedId;

  @override
  Widget build(BuildContext context) {
    return BlocListener<BattleCubit, BattleState>(
      listenWhen: (prev, curr) => curr.bannerChallenge?.id != prev.bannerChallenge?.id,
      listener: (context, state) {
        final challenge = state.bannerChallenge;
        if (challenge != null && challenge.id != _lastAnnouncedId) {
          _lastAnnouncedId = challenge.id;
          SystemSound.play(SystemSoundType.alert);
          HapticFeedback.mediumImpact();
        }
      },
      child: BlocBuilder<BattleCubit, BattleState>(
        buildWhen: (prev, curr) => prev.bannerChallenge?.id != curr.bannerChallenge?.id,
        builder: (context, state) {
          final ChallengeSummary? challenge = state.bannerChallenge;
          if (challenge == null) return const SizedBox.shrink();
          return Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            right: 12,
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.cardSurface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.danger, width: 2),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 8)],
                ),
                child: Row(
                  children: [
                    Text(GameConstants.speciesEmojiFor(challenge.challengerSpecies), style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Wants to fight you!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary)),
                          Text('Lv${challenge.challengerLevel}', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                    ElevatedButton(
                      onPressed: widget.onOpenBattle,
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger, padding: const EdgeInsets.symmetric(horizontal: 12)),
                      child: const Text('View'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () => context.read<BattleCubit>().dismissIncoming(challenge.id),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
