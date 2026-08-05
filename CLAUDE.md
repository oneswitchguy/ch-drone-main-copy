# HandsOptional Flight Lab

Accessible DJI drone control for iPad, built for pilots flying via switch control, AirPods
head tracking, game controllers and other assistive input. Every UI decision should be
weighed against Switch Control and VoiceOver first.

## Never run `pod install`

`Pods/` is committed and contains **hand-patched DJI source**. Reinstalling overwrites those
patches. `ci_scripts/ci_post_clone.sh` skips it deliberately, and the CI flow instead runs
`ch_clean_ffmpeg.sh` to strip `CFBundleSupportedPlatforms` from DJIWidget's bundled FFmpeg,
which is required for App Store validation.

If a pod-level build setting needs changing, edit `Pods/Pods.xcodeproj` in place.

## Names are inconsistent — this is expected

| Thing | Value |
|---|---|
| Display name (users see) | HandsOptional Flight Lab |
| Short name under the icon | HO Flight (`BUNDLE_NAME`, set in `project.pbxproj`, overrides the xcconfig) |
| Xcode project, target, scheme, source folder | CH Drone 2 |
| Swift module | `CH_Drone_2` |
| Bundle ID | `com.christopherhills.chdrone2` |

The bundle ID is **bound to the DJI API key** registered at developer.dji.com. Changing it
invalidates the key and `registerApp` will fail until a new one is issued.

## Building

Open the **workspace**, not the project:

```sh
open "CH Drone 2.xcworkspace"
```

Command-line build that works without a signing certificate:

```sh
xcodebuild -workspace "CH Drone 2.xcworkspace" -scheme "CH Drone 2" \
  -configuration Release -destination "generic/platform=iOS" \
  CODE_SIGNING_ALLOWED=NO build
```

Verified on Xcode 26.6 / iOS 26.5 SDK. Deployment floor is iOS 18.0 (app and test targets);
the Pods targets are still 15.6, which is fine.

## Adding source files requires editing project.pbxproj

The project is `objectVersion = 54` with no file-system-synchronized groups, so **new files
are not picked up automatically**. Each one needs four entries in
`CH Drone 2.xcodeproj/project.pbxproj`: a `PBXBuildFile`, a `PBXFileReference`, an entry in
the group's `children`, and an entry in the target's `Sources` build phase. Mirror an
existing neighbour such as `ObstacleAvoiding.swift` and use a fresh 24-hex-character UUID.

## Tests only run on physical hardware

The DJI SDK ships an **x86_64-only** simulator slice, so no arm64 iPad simulator is offered
as a destination on Apple Silicon. Anything that links the SDK must run on a device.

Consequently, prefer keeping new logic **free of DJI imports** so it can be unit-tested
without the SDK. `@testable import CH_Drone_2` in `CHDroneTests/`.

## Abstracting the SDK

DJI's classes are concrete and SDK-constructed, so anything needing a stand-in goes through
a protocol. The established pattern, all in `CH Drone 2/Virtual Controls/`:

- `FlightControlling` — the subset of `DJIFlightController` the app uses
- `ObstacleAvoiding`, `LandingAssisting` — with `Simulated*` implementations for debug
- `Aircraft` — the product itself; note the member is `flightControl`, not
  `flightController`, because Swift has no covariant property witnesses and `DJIAircraft`'s
  own concrete property cannot be shadowed

Follow this pattern rather than reaching for `DJI*` types directly in view models.

## Control path

All input — switch grid, on-screen joystick, gamepad, head tracking — collapses into a
single `VirtualControlsState`, sent at 10 Hz from `FlightViewModel.sendControlsData()`.
Virtual stick runs in velocity mode with a body coordinate system.

SDK command ceilings, quoted from `DJIFlightControllerBaseTypes.h`: **±15 m/s** horizontal,
**±4 m/s** vertical, **±100 °/s** yaw. Note that `VirtualControlsState.swift` interpolates
roll and pitch over `0...100`, which exceeds the documented range — unresolved, see
`docs/dji-virtual-stick-sport-mode.md`.

## Style

UIKit with Combine, plus SwiftUI for newer leaf views. `@ValueSubject` is the in-house
current-value publisher wrapper. Logging via swift-log with a per-file `Logger(label:)`.
Match the surrounding file's comment density and naming rather than importing new idioms.
