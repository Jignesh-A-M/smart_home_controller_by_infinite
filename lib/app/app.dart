import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:smart_home_controller_by_infinite/infrastructure/theme/app_theme.dart';
import 'package:smart_home_controller_by_infinite/ui/quick_tile/bloc/quick_tile_state.dart';

import '../domain/repository/home_repository.dart';
import '../domain/transport/quick_tile_gateway.dart';
import '../infrastructure/local/sqlite_home_store.dart';
import '../infrastructure/network/api_client.dart';
import '../infrastructure/platform/android_quick_tile_gateway.dart';
import '../infrastructure/repository/home_repository_impl.dart';
import '../infrastructure/transport/mqtt_device_transport.dart';
import '../ui/common/temperature_scope.dart';
import '../ui/home_screen/bloc/home_cubit.dart';
import '../ui/home_screen/presentation/home_screen.dart';
import '../ui/quick_tile/bloc/quick_tile_cubit.dart';
import '../ui/scenes_screen/bloc/scene_bloc.dart';
import '../ui/scenes_screen/bloc/scene_events.dart';
import '../ui/scenes_screen/presentation/scenes_screen.dart';
import '../ui/schedules_screen/bloc/schedule_bloc.dart';
import '../ui/schedules_screen/bloc/schedule_events.dart';
import '../ui/schedules_screen/presentation/schedules_screen.dart';
import '../ui/settings_screen/bloc/settings_cubit.dart';
import '../ui/settings_screen/bloc/settings_state.dart';
import '../ui/settings_screen/presentation/settings_screen.dart';
import 'bloc/navigation_cubit.dart';

class InfiniteHomeApp extends StatelessWidget {
  const InfiniteHomeApp({super.key, this.repository, this.quickTileGateway});

  final HomeRepository? repository;
  final QuickTileGateway? quickTileGateway;

  // Share one repository across dashboard and event-based Scenes Bloc.
  @override
  Widget build(BuildContext context) {
    return RepositoryProvider<HomeRepository>(
      create: (context) {
        return repository ??
            HomeRepositoryImpl(
              api: createApiClient(),
              transport: MqttDeviceTransport(),
              transportFactory: (settings) => MqttDeviceTransport(settings: settings),
              store: SqliteHomeStore(),
            );
      },
      child: BlocProvider(
        create: (context) {
          return SettingsCubit(repository: context.read<HomeRepository>())..load();
        },
        child: BlocBuilder<SettingsCubit, SettingsState>(
          buildWhen: (previous, current) {
            bool a = previous.isLoading != current.isLoading;
            bool b = previous.saved.darkMode != current.saved.darkMode;
            bool c = previous.saved.temperatureUnit != current.saved.temperatureUnit;
            return a || b || c;
          },
          builder: (context, settingsState) {
            if (settingsState.isLoading) {
              return const MaterialApp(
                home: Scaffold(body: Center(child: CircularProgressIndicator())),
              );
            }
            return MultiBlocProvider(
              providers: [
                BlocProvider(create: (context) => HomeCubit(context.read<HomeRepository>())..start(), lazy: false),
                BlocProvider(create: (context) => SceneBloc(repository: context.read<HomeRepository>())),
                BlocProvider(create: (context) => ScheduleBloc(repository: context.read<HomeRepository>())),
                BlocProvider(
                  create: (context) => QuickTileCubit(
                    repository: context.read<HomeRepository>(),
                    gateway: quickTileGateway ?? AndroidQuickTileGateway(),
                    home: context.read<HomeCubit>(),
                    scenes: context.read<SceneBloc>(),
                    settings: context.read<SettingsCubit>(),
                  )..start(),
                  lazy: false,
                ),
              ],
              child: MaterialApp(
                title: 'Infinite Home',
                debugShowCheckedModeBanner: false,
                themeMode: settingsState.saved.darkMode ? ThemeMode.dark : ThemeMode.light,
                builder: (context, child) => TemperatureScope(unit: settingsState.saved.temperatureUnit, child: child!),
                theme: AppTheme.lightTheme(context),
                darkTheme: AppTheme.darkTheme(context),
                home: const HomeShell(),
              ),
            );
          },
        ),
      ),
    );
  }
}

// Keep both pages alive so navigation preserves search and scene run progress.
class HomeShell extends StatelessWidget {
  const HomeShell({super.key});

  static const destinations = [
    NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
    NavigationDestination(
      icon: Icon(Icons.auto_awesome_outlined),
      selectedIcon: Icon(Icons.auto_awesome),
      label: 'Scenes',
    ),
    NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule), label: 'Schedules'),
    NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => NavigationCubit(),
      child: BlocListener<QuickTileCubit, QuickTileState>(
        listenWhen: (previous, current) => previous.openScenesVersion != current.openScenesVersion,
        listener: (context, state) {
          context.read<NavigationCubit>().select(1);
        },
        child: BlocBuilder<NavigationCubit, int>(
          builder: (context, selected) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                return Scaffold(
                  body: Row(
                    children: [
                      if (wide) ...[
                        SafeArea(
                          child: NavigationRail(
                            selectedIndex: selected,
                            labelType: NavigationRailLabelType.all,
                            onDestinationSelected: (value) => select(index: value, context: context),
                            destinations: [
                              for (final destination in destinations) ...[
                                NavigationRailDestination(
                                  icon: destination.icon,
                                  selectedIcon: destination.selectedIcon,
                                  label: Text(destination.label),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                      Expanded(
                        key: const ValueKey('home-pages'),
                        child: IndexedStack(
                          index: selected,
                          children: const [HomeScreen(), ScenesScreen(), SchedulesScreen(), SettingsScreen()],
                        ),
                      ),
                    ],
                  ),
                  bottomNavigationBar: wide
                      ? null
                      : NavigationBar(
                          selectedIndex: selected,
                          onDestinationSelected: (value) => select(index: value, context: context),
                          destinations: destinations,
                        ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void select({required int index, required BuildContext context}) {
    context.read<NavigationCubit>().select(index);
    if (index == 1) {
      context.read<SceneBloc>().add(ScenesRefreshRequested());
    }
    if (index == 2) {
      context.read<ScheduleBloc>().add(RefreshSchedules());
    }
  }
}
