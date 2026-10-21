import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../mascot/mascot_asset_resolver.dart';
import '../../mascot/mascot_catalog.dart';
import '../../mascot/mascot_cubit.dart';
import '../../mascot/mascot_view.dart';

typedef MascotArtworkBuilder = Widget Function(
    BuildContext context, MascotDefinition mascot, bool animate);

class MascotSettingsPage extends StatelessWidget {
  const MascotSettingsPage(
      {super.key,
      required this.preferences,
      required this.resolver,
      this.artworkBuilder});
  final MascotCubit preferences;
  final MascotAssetResolver resolver;
  final MascotArtworkBuilder? artworkBuilder;

  Widget _art(BuildContext context, MascotDefinition mascot, bool animate) =>
      artworkBuilder?.call(context, mascot, animate) ??
      MascotView(
          mascot: mascot,
          resolver: resolver,
          size: animate ? 112 : 64,
          interactive: animate,
          animationsEnabled:
              animate && preferences.state.desired.animationsEnabled,
          routeVisible: ModalRoute.of(context)?.isCurrent ?? true);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Mascot')),
        body: BlocBuilder<MascotCubit, MascotState>(
          bloc: preferences,
          builder: (context, state) {
            final favorite = MascotCatalog.findById(state.desired.selectedId) ??
                MascotCatalog.defaultMascot;
            final readOnly = state.saveState == MascotSaveState.readOnly;
            return Center(
                child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: MascotCatalog.all.length + 1,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(child: _art(context, favorite, true)),
                          Text('Your mascot: ${favorite.displayName}',
                              style: Theme.of(context).textTheme.titleLarge),
                          const Text(
                              'Touch your mascot to change its animation. Your choice stays on this device.'),
                          const SizedBox(height: 8),
                          const Text(
                              'All 13 mascots are included and work offline. Each has four animations.'),
                          if (readOnly)
                            const Text(
                                'These settings were saved by a newer app. Update the app to change them.'),
                          if (state.saveState == MascotSaveState.pending)
                            const Text('Saving your choice…'),
                          if (state.saveState == MascotSaveState.saved)
                            const Text('Saved on this device'),
                          if (state.saveState == MascotSaveState.error)
                            Row(children: [
                              const Expanded(
                                  child: Text(
                                      'Your choice could not be saved yet.')),
                              TextButton(
                                  onPressed: preferences.retrySave,
                                  child: const Text('Retry save')),
                            ]),
                          SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Animate mascot'),
                              subtitle: Text(MediaQuery.disableAnimationsOf(
                                      context)
                                  ? 'System reduced motion is on. Mascots stay still.'
                                  : 'Randomly play the four animations of your favorite.'),
                              value: state.desired.animationsEnabled,
                              onChanged: readOnly
                                  ? null
                                  : preferences.setAnimationsEnabled),
                          const Divider(),
                        ]);
                  }
                  final mascot = MascotCatalog.all[index - 1];
                  final selected = mascot.id == favorite.id;
                  return Semantics(
                      selected: selected,
                      container: true,
                      child: Card(
                        child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(children: [
                              _art(context, mascot, false),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                    Text(mascot.displayName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium),
                                    TextButton(
                                        key: ValueKey('choose-${mascot.id}'),
                                        style: TextButton.styleFrom(
                                            minimumSize: const Size(48, 48)),
                                        onPressed: readOnly
                                            ? null
                                            : () => preferences
                                                .selectMascot(mascot.id),
                                        child: Text(selected
                                            ? 'Selected'
                                            : 'Use ${mascot.displayName}')),
                                  ])),
                            ])),
                      ));
                },
              ),
            ));
          },
        ),
      );
}
