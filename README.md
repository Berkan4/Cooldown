# Cooldown

Cooldowns and countdowns for Android and iPhone, with home-screen widgets and reminders.

- **Two ways to set one:** a duration ("in 3 days") or a date & time ("19 Nov 2026, 00:00").
- **Repeat:** every N hours/days/weeks/months/years, either
  - *Wait until I tap "Done"*: it stays at **Ready** until you mark it done, then the next round starts from that moment (watering plants), or
  - *automatic*: rolls straight into the next round (bin day, rent).
- **Finish message (optional)**, e.g. "Water your plants!". It is shown in the reminder, on the card and on the widget when the cooldown ends.
- **Reminder per cooldown:** off, silent, vibrate, sound, or sound + vibration. The ▶ button next to it shows a test reminder. On iPhone, vibration follows sound, so "Vibrate" arrives like "Silent". Repeating cooldowns queue the next 5 reminders, so they keep coming even if you don't open the app.
- **Two list styles:** big coloured cards, or a compact list to see more at a glance (toggle in the top bar).
- **Time format:** days by default. You can switch to weeks + days, hours, d/h/m or automatic, app-wide in Settings or per cooldown.
- **Widgets are optional.** Each widget shows one cooldown you pick. Its background uses the cooldown's colour, and a slider in the editor sets how see-through it is, from solid to fully transparent. On Android the same setting is also in the widget's settings (long-press it → settings); both always show the same value. The cooldown itself is chosen when the widget is added:
  - Android: a picker appears when you add the widget (long-press the widget → reconfigure to change it). You can also tap ⋮ → "Add to home screen" in the app.
    Tapping a widget opens that cooldown in the app (with a Done button when it is ready).
    The widget picker offers three starting sizes: **Cooldown 1x1**, **Cooldown 1x2** and **Cooldown 4x2**. "Add to home screen" in the app uses 1x1. Each one can be resized from 1x1 up to 4x2 and bigger. 1x1, 1x2, 2x1 (up to 4x1), 2x2 and 4x2 each get their own layout; 4x2 also shows the end date.
  - iOS: home screen (small/medium) and lock screen (circular/rectangular/inline). Long-press → *Edit Widget* → choose the cooldown.

## Project layout

```
lib/                          Flutter app (shared by both platforms)
  models/cooldown.dart        data + repeat logic
  utils/format.dart           "23 days", "3w 2d", "4h 12m" …
  services/store.dart         storage shared with the widgets
  services/notifications.dart scheduled reminders
  screens/                    list, editor, settings
android/app/src/main/kotlin/  Android widget, widget picker
ios/CooldownWidget/           iOS WidgetKit extension (Swift)
test/                         unit tests for the repeat/format logic
```

The widgets are native (Kotlin and Swift) and read the same JSON the app writes. The repeat and format rules exist three times: Dart, Kotlin, Swift. If you change one, change the other two.

## 1. Set up and run on Android (works on Windows)

Requirements: Flutter **3.35 or newer** and Android Studio (for the Android SDK).

Open a terminal in the folder where you cloned this project (the one containing `pubspec.yaml`), then run:

```powershell
cd <path-to-your-Cooldown-folder>                     # e.g. C:\Users\you\projects\Cooldown
powershell -ExecutionPolicy Bypass -File .\setup.ps1   # flutter create + pub get + tests
flutter run                                           # phone connected via USB
```

`setup.ps1` runs `flutter create`, which only adds the platform files that are missing (Gradle wrapper, iOS Runner project, icons). It does not overwrite the files that are already here.

For an installable APK: `flutter build apk --release`. The APK is written to `build\app\outputs\flutter-apk\app-release.apk`.

On the phone:
- Allow notifications when the app asks.
- Settings → **On-time reminders**: on Android 14+, without this permission reminders can arrive up to about 10 minutes late.
- Some phone makers (Xiaomi, Huawei, Samsung with battery optimisation) can block background alarms. If reminders don't arrive, set the app's battery mode to "Unrestricted".

## 2. iPhone (needs a Mac with Xcode 15+)

Apple only lets you build iOS apps on a Mac. Copy or clone the folder to the Mac, then:

1. `flutter pub get`, then `cd ios && pod install`, then `open Runner.xcworkspace`.
2. **Add the widget target:** File → New → Target… → *Widget Extension*.
   - Product name: `CooldownWidget`
   - Untick *Include Live Activity* and *Include Control*. If *Include Configuration App Intent* is shown, its setting doesn't matter.
   - When Xcode asks to activate the scheme, choose **Cancel**, so the Runner scheme stays selected.
3. In the new `CooldownWidget` group in Xcode, **delete every generated .swift file**. Then drag in `ios/CooldownWidget/CooldownWidget.swift` from this repo, with only the CooldownWidget target ticked.
4. Select the **CooldownWidget** target → General → *Minimum Deployments*: **iOS 17.0**.
5. **App Group**, set on *both* the **Runner** and **CooldownWidget** targets: Signing & Capabilities → + Capability → App Groups → add `group.com.berkan.cooldown`. If you change this ID, also change it in `lib/services/store.dart` and `CooldownWidget.swift`.
6. Select your Apple ID team for both targets under Signing. A free account works for your own phone; the app then has to be re-installed every 7 days.
7. Xcode 15+: Runner target → Build Phases → drag **Embed Foundation Extensions** above **Run Script** (the Flutter "Thin Binary" step). This avoids a "Cycle inside Runner" build error.
8. Run the **Runner** scheme on your iPhone, or use `flutter run` from the terminal.

Optional: to show the banner while the app is open, add this to `ios/Runner/AppDelegate.swift` inside `didFinishLaunchingWithOptions` (before `return`):

```swift
UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
```

## Notes and limits

- Widgets refresh about every minute when the display needs it (hours or minutes formats, or under 2 days left) and otherwise every 15–30 minutes. The OS can delay updates to save battery. Every change in the app refreshes the widgets immediately.
- iOS keeps at most 64 scheduled notifications per app. The app keeps the 60 earliest and tops up the queue every time it's opened.
- Release builds use the debug signing key on Android. That is fine for your own phone; the Play Store needs a proper key.
