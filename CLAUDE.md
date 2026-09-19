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

Verified on Xcode 26.6 / iOS 26.5 SDK, and on Xcode 27.0 running on iOS 27.2. Deployment
floor is iOS 18.0 (app and test targets); the Pods targets are still 15.6, which is fine.

**The app must keep the UIScene life cycle.** Built with the iOS 27 SDK, an app without it is
killed at launch with `EXC_BREAKPOINT` in
`_UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption`. `SceneDelegate` (in
`AppDelegate.swift`, named by `UIApplicationSceneManifest` in Info.plist) creates the window
and hands it to whichever app delegate `main.swift` installed, through
`WindowSceneConnecting`. Do not create windows in `didFinishLaunching`, and use scene
callbacks rather than `application…Active` delegate methods, which UIKit no longer calls.

## Adding source files requires editing project.pbxproj

The project is `objectVersion = 54` with no file-system-synchronized groups, so **new files
are not picked up automatically**. Each one needs four entries in
`CH Drone 2.xcodeproj/project.pbxproj`: a `PBXBuildFile`, a `PBXFileReference`, an entry in
the group's `children`, and an entry in the target's `Sources` build phase. Mirror an
existing neighbour such as `ObstacleAvoiding.swift` and use a fresh 24-hex-character UUID.

A **resource** is the same, except the last entry goes in the target's `Resources` phase
instead, and it needs one `PBXBuildFile` *per target that bundles it* against the single
shared `PBXFileReference`. `Drone.reality` is the worked example: it is in both the app's
Resources phase and SceneLab's, because both mount `SimulatorScene`.

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
**±4 m/s** vertical, **±100 °/s** yaw.

Scaling is spread across two files and is easy to misread. `MovementType.baselineValue`
(`0.01` horizontal, `0.25` vertical and yaw) is multiplied by a speed multiplier, clamped to
`-1...1`, then interpolated over `0...100` or `0...4` in `VirtualControlsState.controlData`.
The small baseline is what keeps the `0...100` range sane — **do not change one without the
other**. Full deflection commands about 2 m/s, not 100.

Nothing clamps the result to the ceilings above, and the multipliers are unbounded text
fields in `Settings.bundle`. See `docs/virtual-stick-command-scaling.md`.

## Simulator

`CH Drone 2/Simulator/` is a shipped practice mode, not a debug aid — reachable from the
connection screen via **Practise Without a Drone**, which calls
`ConnectionManager.startSimulation()`.

It works by substitution, not by a parallel code path. `SimulatorAircraft.flightControl`
gets a `SimulatedFlightController`, and every existing input — switch grid, joystick,
gamepad, AirPods head tracking — flies it unchanged. `FlightViewModel` is unaware.

| File | Role |
|---|---|
| `FlightModel` | The flying. Pure Swift, **no DJI imports**, so it unit-tests on the Mac |
| `SimulatedFlightController` | The only file here that imports the SDK. Translation only |
| `ProceduralMesh` | Merges many primitives into one mesh. Pure geometry, **no DJI or RealityKit types on its inputs**, so it unit-tests on the Mac |
| `SimulatorScene` | The RealityKit scene. World built in code; airframe loaded from `Drone.reality` |
| `Drone.reality` | The airframe. The scene's only shipped asset |
| `SimulatorView` / `SimulatorViewModel` | Readouts and the two controls the switch grid lacks |
| `SimulatorViewController` | Stands in for `FlightViewController` behind the controls |

Keep that split. Flying logic goes in `FlightModel` where it can be tested; anything that
needs a `DJI*` type goes in `SimulatedFlightController`.

The world is built in code — ground, grid, pylons, home pad, sky — and should stay that way:
it exists to make motion and orientation legible, which primitives do without an asset
pipeline to keep in step. Textures *drawn at launch* count as code, and there is one:
`SkyGradient` renders an equirectangular gradient with Core Graphics for the skybox.

**The airframe is the exception**, and the only one. It is loaded from `Drone.reality`, a
Reality Composer model with a named part for every arm, motor, rotor, leg and the camera
gimbal. `SimulatorScene.loadAirframe()` scales it to `aircraftSpan`, turns it 180° (the model
is built nose-toward +Z; RealityKit's forward is -Z) and lifts it so the feet rather than the
middle of the body rest on the ground — all three derived from the model's own bounds, so
re-exporting it at a different size cannot silently move it. `rotorNames` and `bodyName` are
the two places the code depends on the model's naming, and both are asserted on load.

If it will not load, `buildProceduralAirframe()` — the boxes-and-sticks airframe it replaced —
stands in, because practice mode with a plain drone beats practice mode with no drone.

The model marks its nose only by shape, so `addHeadingFlash(to:)` puts a yellow flash on the
top-front edge of the body — heading is the hardest thing to read in this scene, and shape is
the first cue to go at distance.

Its rotors are 27:1 bars, so the spin in `update(with:)` shows: advancing the rotor angle by
one step moves 2,503 pixels, against 238 for the disc-shaped rotors an earlier export had.
**Keep every ancestor of the rotors uniformly scaled** — a `Transform` scales before it
rotates, so the blades turn rigidly only while nothing above them scales unevenly.

Note the model roots at a `world` entity wrapping `Drone`, so the load root is not the
airframe itself. Nothing in the code cares — `findEntity(named:)` recurses and `visualBounds`
aggregates — but do not assume the returned entity is the drone.

### Three RealityKit traps this scene already hit

- **An `EnvironmentResource` lights the scene, including `UnlitMaterial`.** Setting
  `content.environment = .skybox(...)` lifted every surface by roughly the sky's average
  brightness — the 0.16 ground rendered at 0.42 and the red north pylon turned pink.
  `SimulatorScene.optOutOfImageBasedLighting()` points the whole scene at an
  `ImageBasedLightComponent(source: .none)`, which restores the colours exactly. Anything
  that adds real lighting later has to revisit that.
- **Equirectangular texture azimuth runs 180° out of phase with compass bearing.** Measured
  with a four-quadrant test sky, not looked up. `SkyGradient.textureAzimuthOffset` holds it.
- **`Drone.reality`'s materials are `ShaderGraphMaterial` and need light to be any colour at
  all.** Under the scene-wide empty light above they render black. `lightAirframe()` sets an
  `ImageBasedLightReceiverComponent` on the aircraft alone, pointed at the sky — the
  component is inherited and the nearest one up the hierarchy wins, so this overrides the
  root's for that subtree only. `addHeadingFlash(to:)` then points the flash back at the
  empty light so its yellow does not wash out. Verified by screenshot diff: swapping the
  airframe in changes only pixels inside the airframe's own footprint, and the flash renders
  at the same RGB it did before.

`FlightModel` works in **East-North-Up** with the origin at the take-off point. This is not
DJI's frame — `DJISimulatorState` reports X as east, Y as north and Z as *negative* when
above home, so converting is `(x, y, -z)`. `SimulatorScene` converts again for RealityKit,
which is Y-up with north at -Z.

Because `FlightModel` has no imports beyond Foundation, the fastest way to check a change
is to compile it on the Mac rather than wait for a device:

```sh
swiftc "CH Drone 2/Simulator/FlightModel.swift" \
       "CH Drone 2/Virtual Controls/VirtualStickLimits.swift" \
       your_harness.swift -o check && ./check
```

`ProceduralMesh.swift` compiles the same way — it imports RealityKit, which exists on macOS
too, and nothing on `MeshBuilder`'s input side is a RealityKit type. The harness file has to
be called `main.swift` if it uses top-level code.

### SceneLab — looking at the scene without a device

`SimulatorScene` has the same problem one level up: the app links the SDK, so there is no
arm64 iPad simulator to run it in, and judging how something *looks* through a device
install is a ten-minute loop per decision.

The **SceneLab** target exists for that. It is a bare SwiftUI app that compiles
`FlightModel.swift`, `SimulatorScene.swift` and `VirtualStickLimits.swift` **by reference** —
no copies, no second source of truth — alongside `SceneLab/SceneLabApp.swift`. It links
nothing, so it runs in the iPad simulator and in Xcode Previews.

```sh
xcodebuild -workspace "CH Drone 2.xcworkspace" -scheme SceneLab \
  -destination "platform=iOS Simulator,name=iPad Pro 11-inch (M5)" build

xcrun simctl install booted "$DERIVED/Build/Products/Debug-iphonesimulator/SceneLab.app"
xcrun simctl launch booted com.christopherhills.SceneLab -flyOnLaunch YES
xcrun simctl io booted screenshot shot.png
```

`-flyOnLaunch YES` flies the canned circuit with nothing to tap, so build → launch →
screenshot is scriptable. Without it, sliders scrub the aircraft to a pose and snap the
camera to it, and `-altitude` / `-distance` / `-heading` / `-bank` set that pose up front.

Two things make the screenshots usable as a regression test. Pin the status bar first
(`xcrun simctl status_bar <device> override --time "09:41"`) or the clock alone moves ~2000
pixels between runs; with it pinned, identical builds produce byte-identical PNGs. And note
that the pose arguments are read from `ProcessInfo.arguments`, not `UserDefaults`, because
`UserDefaults` silently drops a `-key value` pair whose value starts with a minus — which
quietly ignored every negative heading until it was noticed.

SceneLab ships to nobody and has no tests. Deleting the target and `SceneLab/` leaves the
app untouched. Two things to know when working on it:

- It has **no Pods xcconfig**, which is what keeps the SDK out. Do not give it one.
- `SceneLabApp.swift` imports both SwiftUI and RealityKit, and both declare `Scene`, so the
  `App` conformance has to say `some SwiftUI.Scene`.

## Style

UIKit with Combine, plus SwiftUI for newer leaf views. `@ValueSubject` is the in-house
current-value publisher wrapper. Logging via swift-log with a per-file `Logger(label:)`.
Match the surrounding file's comment density and naming rather than importing new idioms.
