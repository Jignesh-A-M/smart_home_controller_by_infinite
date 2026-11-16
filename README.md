# Infinite Home - Smart Home Controller

A Flutter assignment that controls a simulated smart home using REST and MQTT.
It includes rooms, device controls, scenes, schedules, favourites, offline data,
sensor history and an Android quick tile. No real smart-home hardware or Firebase
account is needed.

The original requirements are in the
[assignment PDF](docs/Flutter_Assignment_Smart_Home_Controller.pdf).

## Run the app on your own computer

These steps target **Android**, using a phone or Android emulator. Other platforms
have not been verified. Commands below use Windows PowerShell. Other shells need
their matching commands; for example, use `npm` instead of `npm.cmd`.

### 1. Get the source and tools

Download and extract the submitted source, or clone the repository once its link
is provided. Open the folder that contains `pubspec.yaml` and `backend/`.

Install Flutter, Node.js, Android Studio and the Android SDK. The development setup
used Flutter **3.44.0**, Dart **3.12.0** and Node.js **22.15.0**. The project needs
Dart 3.12 or later within Dart 3.

Open a terminal in the extracted project folder. If needed, change to it first
(replace this example path with your own):

```powershell
Set-Location 'C:\path\to\smart_home_controller_by_infinite'
```

Then run:

```powershell
flutter doctor
flutter pub get
npm.cmd --prefix backend ci
```

Resolve any Android toolchain errors reported by `flutter doctor` before continuing.
Use the Android Studio JDK. This setup has not yet been fully checked on a clean
second computer; known build issues are listed below.

### 2. Start the REST server - terminal 1

```powershell
npm.cmd --prefix backend run server
```

Keep this terminal open. The server uses `backend/db.json` on port **3000**.
Check it in a browser at `http://127.0.0.1:3000/rooms`. It should return five rooms.

### 3. Start the simulator - terminal 2

Open another terminal in the same project folder:

```powershell
npm.cmd --prefix backend run simulator
```

Keep this terminal open too. It runs device commands, sensor updates and the
scheduler. Wait for `Simulator connected to MQTT` and the command subscription.

The default settings in [backend/src/config.js](backend/src/config.js) are:

- REST: `http://127.0.0.1:3000`
- MQTT: `broker.hivemq.com`, port `1883`
- Topic prefix: `ia/jignesh-08dev808`
- Schedule timezone: `Asia/Kolkata`

The computer and Android device both need internet access for this public broker.
The prefix in the app and simulator must match. Use a unique prefix to avoid
sharing messages with another demo run. If using another prefix, change
it in the backend configuration and app Settings, then restart the simulator.
The `/hub` record's `ia/<yourname>` value is only the supplied placeholder.

### 4. Connect an Android device - terminal 3

For a phone, enable Developer options and USB debugging. Connect it by USB and
accept the authorization prompt. For an emulator, start it from Android Studio.

```powershell
adb devices
flutter devices
```

If `adb` is not found, add the Android SDK `platform-tools` folder to PATH or use
the full path to `adb`.

Replace the quoted value below with the Android device ID shown by those commands:

```powershell
$deviceId = 'YOUR_ANDROID_DEVICE_ID'
adb -s $deviceId reverse tcp:3000 tcp:3000
flutter run -d $deviceId
```

The forwarding command lets the app reach the computer's REST server using
`http://127.0.0.1:3000`. Repeat it after reconnecting USB/ADB. It forwards REST,
not the public MQTT connection. Keep the two backend terminals running.

You can also open the project root in Android Studio, select the Android device
and press Run after setting up the backend and forwarding.

### 5. Check the app connection

On a fresh installation, the defaults match the backend settings above. If the
app already has saved settings, open **Settings**, check the REST URL, broker,
port and prefix, then select **Apply connection**. Saved settings override defaults.

After connection, Home should show five rooms and 18 devices; one fixture device
starts offline. Open a room and try a device control.

For a phone without USB forwarding, use the same reachable LAN as the computer.
Set the app's REST URL to `http://YOUR_COMPUTER_LAN_IP:3000` and allow local port
3000 through the computer's firewall. For the standard Android emulator, the host
can also be reached using `http://10.0.2.2:3000`.

For a release APK used without ADB forwarding, enter the computer's LAN address
in Settings. `127.0.0.1` means the phone itself, so it works only when forwarding
is set up. The installed release APK was verified loading all five rooms over LAN
without forwarding. Both backend processes must still be running; they are not
included in the APK. Full release-flow checks remain pending.

## What each flow does

- **Startup:** loads saved settings and cached home data, then refreshes REST and connects to MQTT.
- **Connection banner:** appears below the app bar. Connected hides after five seconds. Reconnecting and Offline remain visible while unavailable.
- **Home and rooms:** shows room/device counts, lights on, favourites and All lights off. A room opens its own device screen. Back returns to Home with its scroll position kept.
- **Search and favourites:** search by device or room name and change local stars, including while offline.
- **Device controls:** switches for lights, brightness for dimmers, position for blinds, and target temperature/mode for thermostats. Sensors are read-only; unknown types do not crash the app.
- **Pending and failure:** a control shows the requested value and a loader. A matching device reply confirms it. After three seconds without a reply, it rolls back and offers Retry. Sliders send once on release.
- **Scenes:** create, edit, delete and run device actions. Saving a scene does not run it. Results show each device's success/failure; Retry sends only failed actions. Failed saves keep the draft. A scheduled scene cannot be deleted until its schedule reference is removed.
- **Schedules:** create, edit, enable/disable and delete a scene or device schedule. The Node scheduler executes it while the app is closed. Times use Asia/Kolkata. Stored occurrence history prevents repeated dispatch in the same minute or after restart. Missed times are not caught up; failed scheduled actions are not automatically retried.
- **Settings:** light/dark mode, Celsius/Fahrenheit and connection details persist. Clear cache needs confirmation and keeps settings/favourites, while removing downloaded data and history.
- **Sensor history:** open a temperature sensor and select Temperature history. It keeps the last 360 valid received samples per sensor, supports C/F and stays available offline. Gaps over 30 seconds break the chart line. No earlier readings are invented.
- **Android quick tile:** select Use for quick tile on a favourite scene, then add Favourite scene from Android Quick Settings edit controls. A tap opens the app and uses the normal scene flow. It waits up to eight seconds for connection; an offline request is discarded and never replayed later.
- **Offline and recovery:** cached values and timestamps remain visible; unavailable controls are disabled. Search, stars and settings still work. MQTT reconnects with backoff. Failed REST syncs retry separately. Invalid payloads keep confirmed values and offer Refresh; refreshing does not replay commands.

## Architecture and package choices

```text
Flutter UI -> Bloc/Cubit -> Repository
                            |-- Dio -> JSON Server
                            |-- DeviceTransport -> MQTT broker <-> Node simulator
                            |-- SQLite
```

- `lib/domain/`: entities and interfaces.
- `lib/infrastructure/`: models, networking, storage, repository, theme and Android tile gateway.
- `lib/ui/`: screens, widgets and Bloc/Cubit state.
- `backend/src/`: simulator, validation, sensors and scheduler.
- `test/` and `backend/test/`: the main tests.

Scenes and Schedules use Bloc; Home, Settings and focused UI state use Cubit.
Widgets do not call REST, MQTT or SQLite directly. Presentation uses BlocBuilder,
BlocListener and BlocConsumer, without `setState` or BlocSelector.

Main packages, with resolved versions in the lockfiles:

- **flutter_bloc 9.1.1 / equatable 3.0.0:** state management and value equality.
- **Dio 5.11.1:** REST calls and timeout/error handling.
- **mqtt_client 10.14.0:** live MQTT messages and subscriptions.
- **sqflite 2.4.6:** saved home data, preferences, favourites and sensor history.
- **json-server 0.17.4 / Node mqtt 5.16.1:** the mock REST server and simulator.

The existing `cloud_firestore` dependency is used by shared model utilities; it is
not the backend. The chart and native Android tile need no extra package.

## Backend behavior and assumptions

The original [docs/db.json](docs/db.json) stays unchanged. `backend/db.json` is the
working copy, so controls and sensors change its values without changing its schema.
It contains five rooms, 18 devices, four scenes and three schedules.

Commands go to `ia/jignesh-08dev808/device/<id>/set`; replies use the matching
`/state` topic. The simulator waits **200-1500 ms**, drops **10%** of commands
without applying them or replying, and updates online sensors every **10 seconds**.
A dropped command is expected during testing; retry it from the app.

The app adds `commandId` and `state` to its MQTT payload. The simulator echoes the
ID with the saved state and time so an old reply cannot confirm a new request.
Bare assignment-style commands such as `{"on":false}` are also accepted. This
MQTT metadata is not added to the REST database structure.

The simulator writes device state through REST. The app stores only confirmed
values in SQLite; pending values stay in memory. Favourites are local overrides.
Temperature is stored in Celsius and converted for display/input. Dimmer power
and brightness are separate. `d14` starts offline; `d18` has an unsupported type.

Development started with manual REST and MQTT checks, followed by the simulator,
models/repository/storage, core screens, recovery handling and the additional
history/tile/layout work. The focus is the assessment, without accounts or real
hardware integration.

## Tests

Run from the project root:

```powershell
flutter analyze
flutter test
node --test backend/test/scheduler.test.js
```

Latest verified results: **40 core Flutter tests and 4 backend tests pass**;
static analysis is clean. The core tests cover repositories, Bloc/Cubit behavior,
controls, rollback, offline data, rooms, scenes, schedules, settings and additions.
They use fakes, so the public broker is not needed for unit/widget tests.

Another **58 regression tests** are available separately:

```powershell
flutter test un_used/extended_tests
```

These also passed. Older learning/debug tools are kept in
[un_used](un_used/README.md), outside normal runtime and test discovery.

## Issues faced

- **Phone could not reach REST:** JSON Server now binds to all local interfaces. A fresh release installation was stuck reconnecting because its saved URL was `127.0.0.1` with no ADB forwarding. Using the computer LAN URL fixed it. For a forwarded connection, recreate `adb reverse` after reconnection.
- **MQTT disconnects:** socket errors from the public broker use the reconnect path. A broker connection does not prove the simulator is running; device replies still confirm commands.
- **Server restart:** REST recovery was separated from MQTT recovery so the app can resync without restarting Flutter.
- **Old replies and retry messages:** request IDs/freshness checks protect confirmations, and a successful control clears its own failed retry entry.
- **Layout:** resize state loss and thermostat overflow with large text were fixed and checked with tests.
- **Build setup:** local SDK/cache permissions and Firebase plugin/Gradle compatibility required temporary workspace build adjustments. A debug APK was built, but clean-machine native build reproduction still needs checking.

## Pending work and honest limits

- **UDP LAN discovery:** not implemented. The core REST/MQTT flows were completed first; the separate app/simulator UDP request/reply flow that returns the hub ID and IP is still missing. Current offline caching does not provide discovery. A reachable LAN can work without internet, but finding a hub would not make the public MQTT broker reachable; local control would need a local communication path too.
- **Final phone/tablet checks:** responsive layouts and animations have automated checks, but the latest combined device run still needs to be completed after the dedicated room-screen change. This is a verification gap, not a claim of full device coverage.
- **Startup issue:** one earlier debug launch showed Android's no-focused-window/not-responding error. A later launch worked, but the cause has not been confirmed as resolved. It needs another startup check.
- **Clean-machine build:** the setup steps above describe the intended local run. A fresh checkout on another machine has not been fully verified, especially the existing Firebase/Gradle compatibility issue.
- **Demo video:** the final reviewed 2-3 minute recording is not ready. It must show live control, failure rollback/retry and offline mode using the latest build.
- **Repository access:** the final repository link and reviewer access still need to be provided and checked.
- **APK attachment and final checks:** a release APK is installed on the phone, and its REST/MQTT connection was checked over LAN. Full release-flow checks and the final APK attachment still need to be completed; connection success alone is not a full acceptance test.

For the local HTTP setup, build the optional debug APK with:

```powershell
flutter build apk --debug
```

The standard output is `build/app/outputs/flutter-apk/app-debug.apk`. Keep the server
and simulator running when testing it. Before submitting, provide the repository
and video links, and attach the APK if available. Do not include build caches,
`node_modules`, local SDK files, signing keys or personal recordings in the source.
