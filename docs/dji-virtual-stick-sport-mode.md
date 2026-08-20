# Virtual Stick control works in S-mode, contradicting SDK documentation

**Status:** open — observed behaviour contradicts published documentation
**Filed against:** DJI Mobile SDK V4 documentation (`dji-sdk/Mobile-SDK-Doc`)
**Severity:** documentation defect, with a safety-relevant unknown attached
**Date raised:** 2026-08-05

---

## Summary

DJI's Mobile SDK documentation states that Virtual Stick control requires the remote
controller mode switch to be in the **P** position on controllers without an F-Mode, and
describes **S-mode** as the means of *regaining manual control from automated flight*.

In practice, Virtual Stick commands are accepted and flown by a **Mavic 2 Pro with the
mode switch in S**. This has been observed repeatedly in normal use of the CH Drone 2
app, not as a one-off.

Either the documentation is wrong, or S-mode Virtual Stick is unsupported-but-functional
behaviour. Both readings need resolving, because the answer changes what an app can
safely rely on.

---

## Environment

| | |
|---|---|
| SDK | `DJI-SDK-iOS` 4.16.2 (CocoaPods, `~> 4.15`) |
| UX SDK | `DJI-UXSDK-iOS-Beta` 0.4.2 |
| Aircraft | DJI Mavic 2 Pro |
| Remote controller | Mavic 2 standard RC — **P / S / T** switch, no F position |
| App | CH Drone 2 (iPad-only, iOS 18.0 minimum) |
| Build | Xcode 26.6, iOS 26.5 SDK |
| Aircraft firmware | _to fill in_ |
| RC firmware | _to fill in_ |

### Virtual Stick configuration in use

Set immediately before every send, in `FlightViewModel.sendControlsData()`:

```swift
flightController.rollPitchControlMode       = .velocity
flightController.rollPitchCoordinateSystem  = .body
flightController.yawControlMode             = .angularVelocity
flightController.verticalControlMode        = .velocity

flightController.send(controlData) { error in … }
```

Commands are sent on a 10 Hz timer, within the SDK's documented 5–25 Hz window.

---

## What the documentation says

From the [Remote Controller component guide](https://developer.dji.com/mobile-sdk/documentation/introduction/component-guide-remotecontroller.html):

> "P-Mode enables advanced features such as Missions, Virtual Sticks and Intelligent
> Orientation Control on remote controllers that do not have an F-Mode."

> "S-Mode can be used to regain manual control from automated flight."

> "Sport mode uses all positioning aids, adjusts the handling gain values of the aircraft
> in order to enhance the maneuverability, and increases the maximum flight speed to
> 20 m/s. The obstacle avoidance system is disabled in S-Mode."

Read together, these say Virtual Stick should be unavailable in S-mode on a Mavic 2 Pro,
and that moving the switch to S is the documented way to take control *away* from the SDK.

---

## Observed behaviour

Virtual Stick commands are accepted and executed with the mode switch in **S**. The
aircraft flies under app control in that position.

### Details to confirm before filing

These are things only flight testing can establish, and the report is stronger with them:

- [ ] Does `isVirtualStickControlModeAvailable` return `YES` while in S-mode?
- [ ] Does `setVirtualStickModeEnabled(true)` succeed, or was Virtual Stick enabled in
      P-mode and the switch moved to S afterwards? These are materially different claims.
- [ ] Does moving the switch P → S mid-flight interrupt Virtual Stick, or does control
      continue uninterrupted?
- [ ] Are S-mode handling gains applied to Virtual Stick input, i.e. does the aircraft
      feel more responsive than the same commands in P-mode?
- [ ] Is obstacle sensing disabled during S-mode Virtual Stick flight?

---

## Why it matters

**1. Applications cannot tell which envelope they are flying.**
The SDK's Virtual Stick velocity ceilings are fixed and documented in
`DJIFlightControllerBaseTypes.h`:

> "Maximum vertical velocity is defined as 4 m/s"
> "Maximum yaw angular velocity is defined as 100 degrees/s"

with ±15 m/s for roll/pitch in the published API reference. If S-mode applies its own
handling gains on top, the aircraft's *response* to an identical command differs between
switch positions while the command values stay the same — and nothing in the API surfaces
which regime is active.

**2. Obstacle sensing is documented as disabled in S-mode.**
This is the safety-relevant part. CH Drone 2 presents obstacle-avoidance state to the
pilot through `ObstacleAvoiding` and `LandingAssisting`. If those subsystems are inert
whenever the switch is in S, the app may be showing avoidance status that does not
reflect what the aircraft is doing. That matters more than usual here: this app is built
for disabled pilots using switch control and other assistive input, where recovering from
a surprise is slower and harder.

**3. Undocumented-but-working behaviour is not safe to build on.**
If S-mode Virtual Stick is unsupported rather than merely undocumented, a firmware or SDK
update could withdraw it without notice.

---

## Questions for DJI

1. Is Virtual Stick officially supported with the mode switch in S on the Mavic 2 series?
2. If it is, should the Remote Controller component guide be corrected?
3. Do the documented Virtual Stick velocity limits (±15 m/s, ±4 m/s, ±100 °/s) still apply
   unchanged in S-mode, or do S-mode gains alter the aircraft's response to them?
4. Is the obstacle avoidance system disabled during S-mode Virtual Stick flight, as the
   documentation implies for S-mode generally?
5. Is there any API to query the active flight mode, so an app can warn the pilot when
   obstacle sensing is unavailable?

---

## Related

- [`dji-sdk/Mobile-SDK-iOS#62`](https://github.com/dji-sdk/Mobile-SDK-iOS/issues/62) —
  `isVirtualStickControlModeAvailable` incorrectly returns `false` while Virtual Stick can
  still be enabled successfully. Suggests the availability check is already unreliable and
  may not be a trustworthy signal for mode-related preconditions.

## Separate open item in this codebase

Moved to [`virtual-stick-command-scaling.md`](virtual-stick-command-scaling.md).

This section previously claimed that `VirtualControlsState.controlData` interpolating roll
and pitch over `0...100` made sticks saturate at roughly 15% of travel. **That was wrong.**
It read the conversion in isolation and missed the `0.01` baseline applied upstream in
`MovementType.baselineValue`, which is what makes `0.01 × 100 = 1 m/s` at the Medium
multiplier. Full deflection commands about 2 m/s, and nothing saturates.

The real defects found in its place — inconsistent scaling between axes, and an unbounded
user-editable multiplier feeding an un-clamped velocity command — are written up in the
report linked above.

## Measuring the aircraft's real limits indoors

Still needed, and unaffected by the correction above: what the *aircraft* does with an
out-of-range command, and how quickly it responds, can only be established with hardware.
This also answers questions 3 and 4 above.

`DJISimulator` is already in the vendored SDK
(`Pods/DJI-SDK-iOS/iOS_Mobile_SDK/DJISDK.framework/Headers/DJISimulator.h`) and is reached
through `DJIFlightController.simulator`. It runs the simulation **on the aircraft's own
flight controller**, with the motors off — so it answers the question with real firmware,
indoors, with no flight risk.

Velocity does not have to be inferred from position. `DJIFlightControllerState` reports it
directly:

> `velocityX` — "Current speed of the aircraft in the x direction, in meters per second,
> using the N-E-D (North-East-Down) coordinate system."

So ground speed is `hypot(velocityX, velocityY)`, and it keeps reporting during simulator
mode because the flight controller believes it is flying.

Method:

1. Remove the propellers. In simulator mode the aircraft behaves as though airborne.
2. Connect, then call `start(withLocation:updateFrequency:GPSSatellitesNumber:...)`. The
   frequency accepts `[2, 150]` Hz; 50 is ample. Zero the wind with `setWindSpeed(_:)`,
   or steady-state readings will be biased.
3. Enable virtual stick and **sweep** the commanded roll value — 5, 10, 15, 20, 30, 50,
   75, 100 — holding each until the speed settles, then releasing.
4. Record commanded value against `hypot(velocityX, velocityY)`.

The result is a response curve, which is more informative than a single full-deflection
test:

| Curve | Reading |
|---|---|
| Linear to 15, then flat | The clamp is real. `0...100` is a defect; the range should be `0...15` |
| Linear all the way to 100 | No clamp — full stick commands 100 m/s, a worse defect |
| Flattens elsewhere | That value is the true ceiling, and it may be flight-mode dependent |

The run-up in the same recording gives the velocity **lag time constant** — the time to
reach 63.2% of steady state. That is currently estimated at 1.5 s in
`FlightModel.Limits.horizontalResponse`, derived from DJI's published braking distance, and
is the only guessed number in the simulator's flight model.

Running the sweep once in P and once in S answers question 4 above at the same time.

This requires an aircraft, so it does not replace the simulator — it calibrates it.

### Existing logs may already answer the first question

`TelemetryLogger` has been recording `horizontalVelocity` every 2 seconds during real
flights, to timestamped CSVs in the app's Documents directory, reachable over Finder since
`UIFileSharingEnabled` is set. If the maximum ever recorded sits at about 15 m/s across
flights where the sticks were held hard over, the clamp is already evidenced. 2 Hz is too
coarse to fit a time constant, but ample for a ceiling.
