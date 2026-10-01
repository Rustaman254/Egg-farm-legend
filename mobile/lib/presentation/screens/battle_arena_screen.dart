import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../blocs/battle/battle_cubit.dart';
import '../../blocs/farm/farm_bloc.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/battle_stats.dart' as bstats;
import '../../core/theme/app_theme.dart';
import '../../data/models/battle.dart';
import '../../data/models/creature.dart';
import '../widgets/ability_badges.dart';
import '../widgets/brand_app_bar.dart';

String _short(String address) => '${address.substring(0, 6)}...${address.substring(address.length - 4)}';

double _wagerWhole(String? wagerWei) {
  if (wagerWei == null || wagerWei == '0' || wagerWei.isEmpty) return 0;
  final v = BigInt.tryParse(wagerWei) ?? BigInt.zero;
  return v / BigInt.from(10).pow(18);
}

class BattleArenaScreen extends StatefulWidget {
  final String wallet;
  const BattleArenaScreen({super.key, required this.wallet});

  @override
  State<BattleArenaScreen> createState() => _BattleArenaScreenState();
}

class _BattleArenaScreenState extends State<BattleArenaScreen> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const BrandAppBar(title: 'Battle Arena', icon: Icons.sports_kabaddi),
      body: BlocConsumer<BattleCubit, BattleState>(
        listenWhen: (prev, curr) => prev.lastResult != curr.lastResult || prev.error != curr.error,
        listener: (context, state) {
          if (state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.error!), backgroundColor: AppColors.danger));
          }
          if (state.lastResult != null) {
            _showDuelResult(context, state.lastResult!, state.abilityCatalog);
          }
        },
        builder: (context, battleState) {
          return BlocBuilder<FarmBloc, FarmState>(
            builder: (context, farmState) {
              final creatures = farmState is FarmLoaded ? farmState.creatures.where((c) => !c.isDead).toList() : <Creature>[];
              if (creatures.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'You need at least one living creature to enter the Battle Arena.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted),
                    ),
                  ),
                );
              }

              final selectedCreature = creatures.where((c) => c.tokenId == _selected).firstOrNull;

              return ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  if (battleState.bannerChallenge != null) _IncomingBanner(challenge: battleState.bannerChallenge!, wallet: widget.wallet, creatures: creatures),
                  _sectionLabel('Pick a creature'),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 92,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: creatures.length,
                      separatorBuilder: (context, index) => const SizedBox(width: 8),
                      itemBuilder: (context, i) {
                        final c = creatures[i];
                        final isSelected = c.tokenId == _selected;
                        return GestureDetector(
                          onTap: () => setState(() => _selected = c.tokenId),
                          child: Container(
                            width: 76,
                            padding: const EdgeInsets.all(6),
                            decoration: cardPopDecoration(
                              borderColor: isSelected ? AppColors.accent : AppColors.forRarity(c.rarity),
                              radius: 16,
                              borderWidth: isSelected ? 3 : 2,
                              small: true,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(GameConstants.speciesEmojiFor(c.species), style: const TextStyle(fontSize: 26)),
                                Text(GameConstants.speciesName(c.species), style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                Text('Lv${bstats.levelForCareScore(c.careScore)}', style: const TextStyle(fontSize: 9, color: AppColors.secondary, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  if (selectedCreature != null) ...[
                    const SizedBox(height: 12),
                    _SelectedCreaturePanel(
                      creature: selectedCreature,
                      catalog: battleState.abilityCatalog,
                      isFighting: battleState.isFighting,
                      onFightWild: () => context.read<BattleCubit>().fightWild(selectedCreature.tokenId),
                      onPostChallenge: () => context.read<BattleCubit>().postChallenge(selectedCreature.tokenId),
                      openCount: battleState.myChallenges.where((c) => c.status == 'open').length,
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionLabel('In the Arena (${battleState.online.where((p) => p.wallet.toLowerCase() != widget.wallet.toLowerCase()).length})'),
                  const SizedBox(height: 8),
                  if (battleState.online.where((p) => p.wallet.toLowerCase() != widget.wallet.toLowerCase()).isEmpty)
                    const Text('No one else is around right now.', style: TextStyle(fontSize: 12, color: AppColors.textFaint))
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: battleState.online
                          .where((p) => p.wallet.toLowerCase() != widget.wallet.toLowerCase())
                          .map((p) => _OnlinePlayerChip(
                                wallet: p.wallet,
                                enabled: selectedCreature != null,
                                onTap: () => _showChallengePlayerSheet(context, p.wallet, creatures, selectedCreature!),
                              ))
                          .toList(),
                    ),
                  const SizedBox(height: 20),
                  _sectionLabel('Open Challenges'),
                  const SizedBox(height: 8),
                  if (battleState.openChallenges.isEmpty)
                    const Text('No open challenges -- post one above to start the arena.', style: TextStyle(fontSize: 12, color: AppColors.textFaint))
                  else
                    ...battleState.openChallenges.map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _OpenChallengeTile(challenge: c, wallet: widget.wallet, creatures: creatures),
                        )),
                  const SizedBox(height: 20),
                  _sectionLabel('Recent Battles'),
                  const SizedBox(height: 8),
                  ...battleState.history.take(8).map((h) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.cardSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Text(GameConstants.speciesEmojiFor(h.opponentSpecies), style: const TextStyle(fontSize: 18)),
                            const SizedBox(width: 8),
                            Expanded(child: Text('vs ${GameConstants.speciesName(h.opponentSpecies)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            Text(h.won ? 'Won' : 'Lost',
                                style: TextStyle(color: h.won ? AppColors.secondary : AppColors.danger, fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      )),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(text.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, color: AppColors.textFaint, letterSpacing: 0.4));

  // Wagers aren't wired up on mobile yet -- see BattleCubit.postChallenge.
  void _showChallengePlayerSheet(BuildContext context, String targetWallet, List<Creature> creatures, Creature preselected) {
    final cubit = context.read<BattleCubit>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Challenge ${_short(targetWallet)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              const Text("They'll see it as a live incoming challenge.", style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  cubit.postChallenge(preselected.tokenId, challengedWallet: targetWallet);
                  Navigator.of(sheetContext).pop();
                },
                child: Text('Challenge with ${GameConstants.speciesName(preselected.species)}'),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showDuelResult(BuildContext context, BattleResult result, Map<String, AbilityInfo> catalog) {
    showDialog(
      context: context,
      builder: (dialogContext) => _DuelResultDialog(result: result, catalog: catalog),
    ).then((_) {
      if (context.mounted) context.read<BattleCubit>().clearResult();
    });
  }
}

class _OnlinePlayerChip extends StatelessWidget {
  final String wallet;
  final bool enabled;
  final VoidCallback onTap;
  const _OnlinePlayerChip({required this.wallet, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: AppColors.cardSurface,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(999), border: Border.all(color: AppColors.border, width: 1.5)),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.circle, size: 8, color: AppColors.secondary),
                const SizedBox(width: 6),
                Text(_short(wallet), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                const Icon(Icons.sports_kabaddi, size: 12, color: AppColors.textFaint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectedCreaturePanel extends StatelessWidget {
  final Creature creature;
  final Map<String, AbilityInfo> catalog;
  final bool isFighting;
  final VoidCallback onFightWild;
  final VoidCallback onPostChallenge;
  final int openCount;

  const _SelectedCreaturePanel({
    required this.creature,
    required this.catalog,
    required this.isFighting,
    required this.onFightWild,
    required this.onPostChallenge,
    required this.openCount,
  });

  @override
  Widget build(BuildContext context) {
    final stats = bstats.battleStats(creature.species, creature.rarity, creature.careScore);
    final level = bstats.levelForCareScore(creature.careScore);
    return Container(
      decoration: cardPopDecoration(borderColor: AppColors.forRarity(creature.rarity)),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${GameConstants.speciesName(creature.species)} · Lv$level', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('HP ${stats.hp} · ATK ${stats.attack} · DEF ${stats.defense}', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          if (creature.abilities.isNotEmpty) ...[
            const SizedBox(height: 6),
            AbilityBadges(abilities: creature.abilities, catalog: catalog),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: isFighting ? null : onFightWild,
                  child: Text(isFighting ? 'Fighting...' : 'Fight Wild'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: openCount >= 3 ? null : onPostChallenge,
            child: Text(openCount >= 3 ? 'Max 3 open challenges' : 'Post Challenge'),
          ),
        ],
      ),
    );
  }
}

class _OpenChallengeTile extends StatelessWidget {
  final ChallengeSummary challenge;
  final String wallet;
  final List<Creature> creatures;

  const _OpenChallengeTile({required this.challenge, required this.wallet, required this.creatures});

  @override
  Widget build(BuildContext context) {
    final isMine = challenge.challengerWallet.toLowerCase() == wallet.toLowerCase();
    final wager = _wagerWhole(challenge.wagerWei);
    return Container(
      decoration: cardPopDecoration(borderColor: isMine ? AppColors.border : AppColors.primary, small: true),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.forRarity(challenge.challengerRarity).withValues(alpha: 0.18),
              border: Border.all(color: AppColors.forRarity(challenge.challengerRarity), width: 2),
            ),
            alignment: Alignment.center,
            child: Text(GameConstants.speciesEmojiFor(challenge.challengerSpecies), style: const TextStyle(fontSize: 20)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: '${GameConstants.speciesName(challenge.challengerSpecies)} ',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    children: [TextSpan(text: 'Lv${challenge.challengerLevel}', style: const TextStyle(color: AppColors.secondary))],
                  ),
                ),
                Text(
                  '${isMine ? 'You' : _short(challenge.challengerWallet)}${wager > 0 ? ' · ${wager.toStringAsFixed(2)} ETH wager' : ''}',
                  style: const TextStyle(fontSize: 10, color: AppColors.textFaint),
                ),
              ],
            ),
          ),
          if (isMine)
            IconButton(icon: const Icon(Icons.close, color: AppColors.danger), onPressed: () => context.read<BattleCubit>().cancel(challenge.id))
          else
            ElevatedButton(
              onPressed: () => _acceptWithPicker(context, challenge, creatures),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14)),
              child: const Text('Accept'),
            ),
        ],
      ),
    );
  }
}

void _acceptWithPicker(BuildContext context, ChallengeSummary challenge, List<Creature> creatures) {
  final cubit = context.read<BattleCubit>();
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Pick your creature vs ${_short(challenge.challengerWallet)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: creatures
                    .map((c) => Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: GestureDetector(
                            onTap: () {
                              cubit.accept(challenge.id, c.tokenId);
                              Navigator.of(sheetContext).pop();
                            },
                            child: Column(
                              children: [
                                Text(GameConstants.speciesEmojiFor(c.species), style: const TextStyle(fontSize: 28)),
                                Text(GameConstants.speciesName(c.species), style: const TextStyle(fontSize: 10)),
                              ],
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

class _IncomingBanner extends StatelessWidget {
  final ChallengeSummary challenge;
  final String wallet;
  final List<Creature> creatures;

  const _IncomingBanner({required this.challenge, required this.wallet, required this.creatures});

  @override
  Widget build(BuildContext context) {
    final wager = _wagerWhole(challenge.wagerWei);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: cardPopDecoration(borderColor: AppColors.danger, small: true),
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Text(GameConstants.speciesEmojiFor(challenge.challengerSpecies), style: const TextStyle(fontSize: 26)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${_short(challenge.challengerWallet)} wants to fight you!', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                Text(
                  'Lv${challenge.challengerLevel}${wager > 0 ? " · ${wager.toStringAsFixed(2)} ETH wager" : ''}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => _acceptWithPicker(context, challenge, creatures),
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
            child: const Text('Accept'),
          ),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => context.read<BattleCubit>().dismissIncoming(challenge.id)),
        ],
      ),
    );
  }
}

class _DuelResultDialog extends StatelessWidget {
  final BattleResult result;
  final Map<String, AbilityInfo> catalog;
  const _DuelResultDialog({required this.result, required this.catalog});

  @override
  Widget build(BuildContext context) {
    final rewardWhole = _wagerWhole(result.rewardFeed);
    final wagerWhole = _wagerWhole(result.wagerWei);
    return AlertDialog(
      title: Text(result.won ? 'Victory!' : 'Defeated...', style: TextStyle(color: result.won ? AppColors.secondary : AppColors.danger, fontWeight: FontWeight.w900)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Column(children: [
                  Text(GameConstants.speciesEmojiFor(result.playerSpecies), style: const TextStyle(fontSize: 32)),
                  Text('You (Lv${result.playerLevel})', style: const TextStyle(fontSize: 11)),
                  AbilityBadges(abilities: result.playerAbilities, catalog: catalog),
                ]),
                const Text('VS', style: TextStyle(fontWeight: FontWeight.bold)),
                Column(children: [
                  Text(GameConstants.speciesEmojiFor(result.opponentSpecies), style: const TextStyle(fontSize: 32)),
                  Text('Foe (Lv${result.opponentLevel})', style: const TextStyle(fontSize: 11)),
                  AbilityBadges(abilities: result.opponentAbilities, catalog: catalog),
                ]),
              ],
            ),
            const SizedBox(height: 10),
            if (result.won) Text('+${rewardWhole.toStringAsFixed(0)} FEED · +${result.xpAwarded} XP', style: const TextStyle(fontWeight: FontWeight.bold)),
            if (wagerWhole > 0)
              Text(
                result.wagerWon ? 'Won the ${wagerWhole.toStringAsFixed(2)} ETH wager!' : 'Lost your ${wagerWhole.toStringAsFixed(2)} ETH wager.',
                style: TextStyle(color: result.wagerWon ? AppColors.secondary : AppColors.danger, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 150),
              child: ListView(
                shrinkWrap: true,
                children: result.log.map((line) => Text(line, style: const TextStyle(fontSize: 11))).toList(),
              ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Continue'))],
    );
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
