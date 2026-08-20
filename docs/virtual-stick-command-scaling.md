# Virtual stick velocity commands are unbounded and inconsistently scaled across axes

**Status:** finding 3 fixed 2026-08-20; finding 2 open as a product decision
**Fixed in:** `VirtualStickLimits.swift`, `VirtualControlsState.controlData`,
`UserDefaults.sanitizedMultiplier(forKey:)`, covered by `CHDroneTests/VirtualStickLimitsTests.swift`
**Filed against:** this codebase (HandsOptional Flight Lab / CH Drone 2)
**Severity:** functional defect, with a safety-relevant latent hazard
**Date raised:** 2026-08-20

Supersedes the "Separate open item in this codebase" section of
[`dji-virtual-stick-sport-mode.md`](dji-virtual-stick-sport-mode.md), whose hypothesis was
wrong. See "Correction" below.

---

## Summary

Three findings, in increasing order of seriousness:

1. **The suspected stick saturation does not happen.** The `0...100` interpolation range is
   compensated by a `0.01` baseline, so full deflection commands about 2 m/s.
2. **Horizontal control reaches 13% of the available envelope, while vertical and yaw reach
   50%.** The axes are scaled inconsistently, and probably not deliberately.
3. **Nothing bounds the result.** The speed multipliers are free-text fields in the iOS
   Settings app with no minimum or maximum, and no code clamps the converted command to the
   SDK's documented ceilings. A plausible value typed into Settings commands a speed the
   app was never designed to reach.

Finding 3 is the one to fix.

---

## Environment

| | |
|---|---|
| SDK | `DJI-SDK-iOS` 4.16.2 |
| Aircraft | DJI Mavic 2 Pro |
| App | HandsOptional Flight Lab, iPad-only, iOS 18.0 minimum |
| Virtual stick config | `.velocity` roll/pitch, `.body` coordinates, `.angularVelocity` yaw, `.velocity` vertical |

---

## The command chain

Every input — switch grid, on-screen joystick, gamepad, AirPods head tracking — collapses
through the same four steps:

```
MovementType.baselineValue              0.01 horizontal, 0.25 vertical and yaw
  × MovementMultipliers value           0.5 … 2.0, user-editable and unbounded
  = VirtualControlsState                clamped to -1...1
  × ClosedRange.interpolatedValue       0...100 roll/pitch and yaw, 0...4 vertical
  = DJIVirtualStickFlightControlData    m/s and °/s
```

Both the switch grid (`CommandGrid.controlsState(multipliers:)`) and the joystick
(`JoystickCommands.AxisOption.virtualControlsState(axisValue:movementMultipliers:)`) apply
the baseline, so neither path can reach full deflection of the `0...100` range.

### What full deflection actually commands

At the "Fastest" multiplier, which defaults to 2.0:

| Axis | baseline | × 2.0 | range | commanded | SDK ceiling | share of envelope |
|---|---|---|---|---|---|---|
| Roll / pitch | 0.01 | 0.02 | `0...100` | **2.0 m/s** | 15 m/s | 13% |
| Vertical | 0.25 | 0.50 | `0...4` | **2.0 m/s** | 4 m/s | 50% |
| Yaw | 0.25 | 0.50 | `0...100` | **50 °/s** | 100 °/s | 50% |

At "Medium" (1.0) every axis halves: 1 m/s horizontal, 1 m/s vertical, 25 °/s yaw.

---

## Finding 1 — no saturation

The earlier concern was that `0...100` against a documented ±15 m/s ceiling meant sticks
saturated at roughly 15% of travel. They do not. `MovementType.baselineValue` is `0.01` for
`pitchForward`, `pitchBackward`, `rollLeft` and `rollRight`
(`CH Drone 2/Virtual Controls/MovementType.swift:43`), and `0.01 × 100 = 1 m/s` at the
Medium multiplier — matching the vertical axis, whose `0.25` baseline against a `0...4`
range also gives 1 m/s.

The pairing is deliberate. It is also entirely undocumented, and the two halves live in
different files with nothing tying them together.

## Finding 2 — inconsistent scaling between axes

Horizontal reaches 13% of what the SDK permits; vertical and yaw reach 50%. Nothing in the
code explains the difference, and the comment on `baselineValue` says only that the values
were "attempted to match DJI default controls".

Two metres per second is a brisk walking pace. That may well be the right maximum for this
app's pilots, and slow is a defensible default when recovering from a mistake is slow. But
it should be a decision on the record rather than a side effect of two constants in
separate files, and the asymmetry with the vertical axis suggests it was not chosen.

## Finding 3 — the commanded velocity is unbounded

`CH Drone 2/Settings.bundle/Root.plist` exposes all five multipliers under "Control Speed
Multiplier Definitions" as `PSTextFieldSpecifier` entries with a `NumbersAndPunctuation`
keyboard and **no `Minimum` or `Maximum` key**.

`UserDefaults.sanitizedFloat(forKey:)`
(`CH Drone 2/Utilities/UserDefaults+Settings.swift:116`) validates only that the stored
value parses as a float. It applies no range check.

So typing `50` into "Fastest" in the iOS Settings app produces:

```
0.01 × 1.0 × 50 = 0.5  →  interpolated over 0...100  →  50 m/s commanded
```

Any value above **15** pushes past the SDK's documented horizontal ceiling. The `-1...1`
clamp in `VirtualControlsState` caps the absolute worst case at 100 m/s.

The aircraft will almost certainly clamp this itself — that is what
[`dji-virtual-stick-sport-mode.md`](dji-virtual-stick-sport-mode.md) sets out to measure —
so the likely outcome is a pilot who sets "Fastest" to 50, gets 15 m/s, and has a control
whose top third does nothing. But the app is relying on the aircraft to enforce a limit it
never states, and firmware is not a validation layer.

### Why this matters more here than it would elsewhere

This app is flown by pilots using switch control, head tracking and other assistive input,
where noticing a problem and recovering from it both take longer than usual. A speed
setting that silently means something different from what it says is a poor fit for that,
and the multipliers are exactly the setting a helper is most likely to adjust on someone
else's behalf.

---

## Recommended fixes

1. ~~**Clamp in `VirtualControlsState.controlData` to the documented ceilings.**~~ **Done.**
   The three ceilings now live in `VirtualStickLimits`, shared with the simulator's
   `FlightModel.Limits` so there is one source of truth. `controlData` clamps every axis on
   the way out.
2. ~~**Bound the multipliers.**~~ **Done.** `UserDefaults.sanitizedMultiplier(forKey:)`
   clamps to `MovementMultipliers.allowedRange` (`0.05...10`). Applied on **read**, because
   the iOS Settings app writes to these keys directly and a setter would never see the
   value. `Settings.bundle` gained a footer stating the range.
3. ~~**Rename `pitchRollAngleRange`.**~~ **Done** — now `pitchRollVelocityRange`. It said
   "Angle" while the control mode is `.velocity`, which is how the saturation hypothesis
   arose in the first place.

Still open:

4. **Replace `0...100` with `0...15`** and rescale the horizontal baseline from `0.01` to
   `0.0667`. That preserves today's behaviour exactly — `0.0667 × 15 ≈ 1 m/s` at Medium,
   unchanged — while making the numbers mean what they say. Do this as a no-op refactor
   first, then change the feel separately if wanted. Left undone because it touches flight
   behaviour if the arithmetic is got wrong, and the guards above remove the urgency.
5. **Decide deliberately whether horizontal should stay at 13% of the envelope**, now that
   the number is visible. This is finding 2, and it is a product decision rather than a
   defect.

### What the fix does not do

The clamp caps commands at the SDK ceiling; it does not restore the lost stick travel. A
pilot who sets "Fastest" to 10 still commands 10 m/s at full deflection and 5 m/s at half —
correct and in range, but a five-fold change in feel from the default. The multiplier bound
limits how far that can go; it does not make large values sensible.

---

## How to verify

The simulator decodes the same `DJIVirtualStickFlightControlData` fields the aircraft
receives, so fixes 1–4 can be exercised on the ground with no aircraft. Findings 1 and 2
are already confirmed by inspection and need no flight at all.

Confirming what the *aircraft* does with an out-of-range command still needs hardware. The
indoor method is in
[`dji-virtual-stick-sport-mode.md`](dji-virtual-stick-sport-mode.md#this-can-be-measured-indoors-without-flying).

---

## Correction

The superseded hypothesis held that sticks saturated at ~15% of travel. That was wrong: it
read `VirtualControlsState.controlData` in isolation and missed the `0.01` baseline applied
upstream. Anything downstream of that reading should be re-checked — in particular, the
simulator's "At limit" warning was built to surface a saturation that does not occur under
default settings, though it remains correct for the unbounded-multiplier case in Finding 3.
