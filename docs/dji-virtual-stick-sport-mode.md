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

Not a DJI issue — recording it here because it surfaced in the same investigation.

`VirtualControlsState.controlData` interpolates roll and pitch over a `0...100` range
(`CH Drone 2/Virtual Controls/VirtualControlsState.swift:73`), where the SDK documents
±15 m/s for those axes in velocity mode. If the aircraft clamps at 15, horizontal sticks
reach full commanded speed at roughly 15% of deflection, making the movement multipliers
far coarser than the UI implies. Needs one instrumented flight to confirm whether this is
a defect or deliberate.
