# A tap on the screen does not disengage AirPods head tracking

**Status:** fixed in `e36bd63` and confirmed on the iPad with AirPods, 2026-09-19 — on touch-down, not tap (see *Resolution* at the end)
**Filed against:** this codebase (HandsOptional Flight Lab / CH Drone 2), `feature/flight-simulator-seam` at `edbc1be`
**Severity:** accessibility and safety defect — the pilot's most instinctive "stop" gesture silently does nothing for the one control mode they cannot physically let go of
**Date raised:** 2026-09-12

---

## Summary

Tapping anywhere on the flight screen is supposed to disengage the active control and
re-centre the joystick. It does — but **only when the on-screen touch joystick is what is
flying**. When AirPods head tracking is the active source, the same tap is swallowed and the
aircraft keeps following the pilot's head.

The behaviour already works correctly when tapping an on-screen command button such as Pitch
Forward, which is what makes the gap easy to miss: the disengage *appears* to work, because
the button path takes a different, unconditional route.

One line is responsible.

---

## Expected behaviour

Any tap on the flight screen stops head tracking from driving the aircraft and returns the
joystick to centre, regardless of which source is active.

## Actual behaviour

| Pilot action | Touch joystick active | Head tracking active |
|---|---|---|
| Tap an on-screen command button (Pitch Forward, …) | disengages | **disengages** |
| Move a gamepad stick or D-pad | disengages | **disengages** |
| Automatic return-to-home countdown starts | disengages | **disengages** |
| AirPods stop reporting for 0.75 s | n/a | disengages |
| **Tap anywhere else on the screen** | disengages | **nothing happens** |

---

## Cause

The tap recogniser is installed screen-wide and reaches the view model correctly. The defect
is in which interrupt it asks for.

`ControlsContainerViewController.swift:40-43` adds `disengageTapGestureRecognizer` to the
container's root view — so it does cover the whole flight screen, the video feed and the
simulator scene included. Its handler (`:137-139`) calls:

```swift
viewModel.disengageOnScreenJoystickControl()
```

which is (`FlightViewModel.swift:179-181`):

```swift
func disengageOnScreenJoystickControl() {
    joystickControlsModel.interruptScreenControl()
}
```

and `interruptScreenControl` (`JoystickControlsModel.swift:91-96`) is the narrowest of the
three interrupts:

```swift
func interruptScreenControl() {
    guard uiState.source == .screen else {
        return
    }

    interrupt()
}
```

When head tracking is flying, `uiState.source` is `.airPods`, the guard fails, and the method
returns having done nothing.

There are three interrupts, in widening order, and the tap is wired to the narrowest:

| Method | Interrupts | Used by |
|---|---|---|
| `interruptScreenControl()` | `.screen` only | **the screen-wide tap** |
| `interruptNonJoystickControl()` | `.screen`, `.airPods` | gamepad sticks and D-pad (`FlightViewModel.swift:681-721`) |
| `interrupt()` | everything | command buttons (`:194`, `:273`), RTH countdown (`:326`), motion timeout |

### Why the command buttons already work

`setKeyState(keyDown:position:column:)` opens with an unconditional interrupt
(`FlightViewModel.swift:193-194`):

```swift
func setKeyState(keyDown: Bool, position: CommandPair.Position, column: Int) {
    joystickControlsModel.interrupt()
```

No guard, no source check. That is the behaviour this report asks to be extended to a plain
tap.

---

## Suggested fix

Widen the tap by one method call:

```swift
func disengageOnScreenJoystickControl() {
    joystickControlsModel.interruptNonJoystickControl()
}
```

`interruptNonJoystickControl()` covers `.screen` and `.airPods` and deliberately leaves the
physical gamepad sticks alone (`ControlSource.isJoystick`). That is the right boundary: a
screen tap should not cancel a stick the pilot is physically holding, and it could not
usefully do so anyway — the gamepad publishers re-assert the held position on their next
tick, so the interrupt would be undone within a frame.

Using the bare `interrupt()` instead would fight the gamepad in exactly that way, so prefer
`interruptNonJoystickControl()`.

The method name `disengageOnScreenJoystickControl` becomes wrong once it does more than the
on-screen joystick, and should be renamed with it (`disengageScreenAndHeadTrackingControl`,
or simply `disengageControl`).

### What must not change

- **The thumb-view exclusion** (`ControlsContainerViewController.swift:141-147`). Touches on
  the joystick thumb are withheld from the recogniser, so dragging the thumb cannot cancel
  itself. That exclusion is load-bearing and must survive the fix.
- **`cancelsTouchesInView = false`** (`:41`). The tap still reaches whatever is underneath, so
  a tap that lands on a command button both disengages and presses the button. Widening the
  interrupt does not change this; the button's own `interrupt()` is then simply redundant.

---

## Two clarifications worth having before the fix

**"Stop headphone motion data" means stop it *controlling*, not stop sampling.**
`HeadphoneMotionManager` is started once in `JoystickControlsModel.init`
(`JoystickControlsModel.swift:24`) and stopped only in `deinit` (`:28`). It samples
continuously, because that is also how the app knows whether AirPods are present at all.
`interrupt()` does not touch it — it sets `airPodsMotionState.isControlling = false`, and
`handleHeadphoneMotion` early-returns on that flag (`:221-230`), so the data keeps arriving
and stops steering. That is the correct outcome and the fix should not try to stop the
manager; doing so would also break availability detection.

**"Re-centre the joystick" is not the same as re-centring the head-tracking neutral.**
`interrupt()` sets `uiState = .idle` and fires `interruptionDriver`, which cancels any
in-flight pan gesture in `JoystickViewController` (`:44-51`) and returns the thumb to centre.
It does **not** call `headphoneMotionManager.recenter()`. The neutral head pose is
re-established on the next engage, after the three-second countdown
(`JoystickControlsModel.swift:140`). That is almost certainly right — a pilot re-engaging
wants neutral taken from where their head is *then* — but it is worth stating so the fix is
not over-scoped into resetting the neutral on every tap.

---

## Open question, not part of the fix

`UITapGestureRecognizer` fires on tap **ended**, so disengage waits for the finger to lift.
For a gesture whose purpose is to stop an aircraft, touch-**down** would be faster and is
what a pilot would expect from a panic tap. Changing this means a `UILongPressGestureRecognizer`
with a zero minimum duration, or a touch handler, and it interacts with the thumb exclusion
above — so it is worth deciding deliberately rather than folding into the one-line fix.

**Decided 2026-09-19: touch-down.** See *Resolution*.

---

## Reproducing

Needs hardware: AirPods with head tracking, and either an aircraft or the simulator
(**Practise Without a Drone** exercises the same path — `SimulatedFlightController` sits
behind the identical `FlightViewModel`, so this reproduces with no aircraft present).

1. Connect AirPods. Tap the joystick thumb to start the three-second countdown and engage
   head tracking.
2. Confirm the aircraft is following head movement.
3. Tap an empty part of the screen — not a button, not the thumb.
4. **Observed:** head tracking continues; the joystick stays off centre; the aircraft keeps
   flying.
   **Expected:** head tracking disengages and the joystick returns to centre.
5. For contrast, repeat to step 3 and tap Pitch Forward instead. Head tracking disengages
   immediately — the behaviour this report asks for everywhere.

---

## Resolution

Fixed 2026-09-19. Christopher asked for disengage **on touch**, so the fix is wider than the
one-line change suggested above.

**Which control it stops.** The screen handler now calls `FlightViewModel.disengageForScreenTouch()`
(renamed from `disengageOnScreenJoystickControl`), which calls a new
`JoystickControlsModel.interruptForScreenTouch()`. That method:

- cancels a head tracking countdown that has not engaged yet. Without this, a pilot who
  touches the screen during the three seconds would have head tracking take over after they
  had asked it to stop. This case was not in the original report.
- then calls `interruptNonJoystickControl()`, as suggested above — so it stops the on-screen
  joystick and head tracking, and leaves a held gamepad stick alone.

`interruptScreenControl()` is unchanged and still used by the two Switch Control observers.

**When it fires.** The `UITapGestureRecognizer` is replaced by a small `TouchDownGestureRecognizer`
(private, at the foot of `ControlsContainerViewController.swift`). It calls its handler from
`touchesBegan` for every finger that lands and never recognises, then fails once the last
finger lifts. A zero-duration long press was rejected, because it misses two fingers landing
together, as the tap did.

Both "must not change" constraints hold. The delegate still withholds thumb touches, and the
recogniser neither cancels nor delays other views' touches (`cancelsTouchesInView` and
`delaysTouchesEnded` are both off).

**What changes for the pilot.** Every touch anywhere except the thumb now disengages head
tracking, and it happens as the finger lands. That includes touches on the gimbal tilt stepper
and on the simulator's top strip (Take Off, Reset, the control link button). Command buttons
already disengaged, through `setKeyState`.

**How it was verified.**

- The app builds clean for device (`generic/platform=iOS`, Release) with no new warnings.
- The recogniser source was dropped, unchanged, into a throwaway harness app. Six XCUITest
  cases were driven through real simulator touches on an iPad Pro 11-inch, alongside a tap and
  a zero-duration long press as controls. All six pass:

  | Case | Touch-down recogniser | Tap (old) | Long press, 0 s |
  |---|---|---|---|
  | Finger held 2 s | fires 2,011 ms before lift | never fires | fires |
  | Five taps in a row | 5 | 5 | 5 |
  | Two fingers land together | fires | **misses** | **misses** |
  | Tap and hold on a button | fires; button still fires on release | — | — |
  | Drag on the thumb | withheld; the thumb's own pan still works | — | — |

**Confirmed on hardware, 2026-09-19.** Christopher ran the build with the fix on the iPad
(iPad Pro 12.9-inch, 6th generation, iOS 27.2) with AirPods, and both halves of the fix
work:

- With head tracking engaged, a touch on the screen disengages it. This is step 4 under
  *Reproducing*, now passing.
- Touching the screen during the three-second countdown cancels it, and head tracking does
  not engage.
