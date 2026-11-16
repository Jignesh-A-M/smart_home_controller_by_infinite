import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/home_snapshot.dart';
import '../home_screen/bloc/home_cubit.dart';
import '../home_screen/bloc/home_state.dart';

class ConnectionStatusBanner extends StatelessWidget {
  const ConnectionStatusBanner({super.key});

  // Rebuild when connection or timed visibility changes in the Cubit.
  @override
  Widget build(BuildContext context) => BlocBuilder<HomeCubit, HomeState>(
    buildWhen: (previous, current) =>
        previous.connection != current.connection || previous.showConnectionBanner != current.showConnectionBanner,
    builder: (context, state) {
      if (!state.showConnectionBanner) {
        return const SizedBox.shrink();
      }

      final connection = state.connection;
      final scheme = Theme.of(context).colorScheme;
      final (label, icon, background, foreground) = switch (connection) {
        HubConnection.connected => (
          'Connected',
          Icons.cloud_done_outlined,
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
        ),
        HubConnection.reconnecting => (
          'Reconnecting to hub…',
          Icons.sync,
          scheme.secondaryContainer,
          scheme.onSecondaryContainer,
        ),
        HubConnection.offline => (
          'Offline · Showing saved data',
          Icons.cloud_off_outlined,
          scheme.errorContainer,
          scheme.onErrorContainer,
        ),
      };
      return Semantics(
        key: const ValueKey('connection-status-banner'),
        container: true,
        liveRegion: true,
        child: Material(
          color: background,
          child: SafeArea(
            top: false,
            bottom: false,
            minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: connection == HubConnection.reconnecting
                      ? CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                          value: MediaQuery.disableAnimationsOf(context) ? .65 : null,
                        )
                      : Icon(icon, size: 18, color: foreground),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class ConnectionStatusBody extends StatelessWidget {
  const ConnectionStatusBody({super.key, required this.child, this.maxContentWidth = 1100});

  final Widget child;
  final double maxContentWidth;

  // Keep the banner below the app bar and the scrollable content below the banner.
  @override
  Widget build(BuildContext context) => Column(
    children: [
      AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 180),
        alignment: Alignment.topCenter,
        child: const ConnectionStatusBanner(),
      ),
      Expanded(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxContentWidth),
            child: child,
          ),
        ),
      ),
    ],
  );
}
