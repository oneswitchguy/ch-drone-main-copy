# Control link over MQTT

HandsOptional Flight Lab streams the pilot's stick positions over MQTT, so that the
**physical joystick mover** can move real sticks to match. This is the contract between the
app, the mover and the Mac monitor. The app's side of it is
`CH Drone 2/Control Link/ControlLinkProtocol.swift`; change the two together.

Status: **test phase.** The app sends only while **Link** is turned on in the simulator's
top strip (Practise Without a Drone). Link is off by default.

## Broker

| | |
|---|---|
| Broker | Mosquitto on Christopher's Mac: `Christophers-MacBook-Pro-5.local`, port **1883** |
| Protocol | MQTT 3.1.1 over plain TCP |
| Authentication | none; trusted local network only |
| Config | `tools/mosquitto/mosquitto.conf` |

Start it on the Mac with:

```sh
brew install mosquitto        # once
mosquitto -c tools/mosquitto/mosquitto.conf -v
```

The first time, macOS asks whether to allow incoming connections. Allow it, or nothing on
the network can connect. The config turns Nagle's algorithm off (`set_tcp_nodelay true`)
so small messages go out at once.

The iPad's broker address is in the Settings app, under HandsOptional Flight Lab, then
Control Link (MQTT).

## Topics

Everything is under `chdrone/v1/`. Every payload is **flat JSON**, with no nesting and no
base64, so ArduinoJson or similar can read it directly.

| Topic | QoS | Retained | Sent by | When |
|---|---|---|---|---|
| `chdrone/v1/stick` | 0 | no | iPad | 10 times a second while the flight controls are active |
| `chdrone/v1/status` | 1 | **yes** | iPad (its Will sends the offline form) | on connect, on disconnect |
| `chdrone/v1/ping` | 0 | no | the Mac monitor | 5 times a second |
| `chdrone/v1/pong` | 0 | no | anything that answers pings | straight away |

### `chdrone/v1/stick`

```json
{"session":"6F1C…","seq":1234,"t":1789821690632,"pitch":0.5,"roll":0,"yaw":-0.25,"throttle":0,"active":true,"source":"simulator"}
```

| Field | Meaning |
|---|---|
| `pitch`, `roll`, `yaw`, `throttle` | Stick position, **-1 to 1**, rounded to 0.001. 0 is centre. |
| `active` | `false` when every axis is at rest |
| `seq` | Goes up by one each message within a session |
| `session` | New each time the app launches. `seq` starts again from 1 |
| `t` | The iPad's clock when sent, milliseconds since 1970 |
| `source` | `"simulator"` (Practise Without a Drone) or `"flight"` (the real flight screen) |

**Stick directions (Mode 2):**

```
      LEFT STICK                      RIGHT STICK
    throttle +1 (climb)             pitch +1 (forward)
          ▲                               ▲
yaw -1 ◀──┼──▶ yaw +1          roll -1 ◀──┼──▶ roll +1
  (left)  │   (right,                (left)  │   (right)
          ▼    clockwise)                    ▼
    throttle -1 (descend)           pitch -1 (back)
```

### What 1.0 means: speed steps are fixed stick amounts

**Full stick (±1)** is the app's on-screen joystick pushed all the way at the **Fastest**
speed step. The app's speed steps come through as fixed fractions of that. With the
default speed multipliers, holding Pitch Forward gives:

| Speed step | Slowest | Slow | Medium | Fast | Fastest |
|---|---|---|---|---|---|
| Pitch deflection | 0.25 | 0.375 | **0.50** | 0.75 | 1.00 |

The on-screen joystick works the same way. At Medium, a full push is ±0.5; set that axis
to Fastest to get the full ±1 range. The fixed amounts can be tuned with the five speed
multiplier fields in the Settings app, because deflection = step multiplier ÷ Fastest
multiplier.

Buttons and the joystick combine axis by axis. The typical test is Pitch Forward held at
Medium while the on-screen joystick does yaw. That arrives as `"pitch":0.5` steady, with
`yaw` following the joystick.

### `chdrone/v1/status` (retained)

```json
{"online":true,"session":"6F1C…","device":"CH iPad","build":"57"}
```

Because it is retained, the mover gets the current status as soon as it subscribes. If
the iPad drops off the network without disconnecting, the broker publishes the same message
with `"online":false`: that is the iPad's MQTT **Will**. It can take up to about 7.5 seconds
(one and a half times the 5-second keepalive), so it is a backstop, not the safety
mechanism. See below.

### `chdrone/v1/ping` and `chdrone/v1/pong`: joining the latency test

The Mac monitor publishes pings:

```json
{"id":42,"from":"monitor-1A2B3C4D","t":1789821690000}
```

Anything that wants its round trip measured answers **immediately** on
`chdrone/v1/pong`. It copies `id`, `from` and `t`, and adds its own name in `by` and its
own clock in `rt`:

```json
{"id":42,"from":"monitor-1A2B3C4D","by":"mover","t":1789821690000,"rt":1789821690012}
```

The iPad already answers as `"ipad"`. If the mover answers as `"mover"`, the monitor shows
its round trip separately. `rt` in milliseconds since 1970 is best. If the mover has no
real-time clock, send `0`: the round trip is still correct, and only the clock offset
figure becomes meaningless.

## Safety requirements for the mover

The mover physically moves sticks, so it must fail to **neutral**:

1. **Return every stick to centre if no `stick` message has arrived for 300 ms.** At
   10 Hz that is three missed messages. This is the real safety mechanism; the others
   are backstops.
2. Return to centre when `status` says `"online":false`.
3. Return to centre when its own connection to the broker drops.
4. Ignore any message whose `seq` is not greater than the last one seen in the same
   `session`. A new `session` resets the count.

## Checking by hand

On the Mac, with Mosquitto running:

```sh
mosquitto_sub -h localhost -t 'chdrone/#' -v
```

shows every message. To send a test ping and see who answers:

```sh
mosquitto_pub -h localhost -t chdrone/v1/ping -m '{"id":1,"from":"cli","t":0}'
```

## The Mac monitor

`tools/ControlLinkMonitor/` is a small Mac app. Open `ControlLinkMonitor.xcodeproj` and
run it, then press Connect. The project is generated from `project.yml` with `xcodegen`.
It shows:

- whether the iPad is online;
- live stick positions;
- the message rate, dropped messages (gaps in `seq`), out-of-order messages and jitter;
- the time since the last message, turning red after 300 ms;
- the round trip to each responder, and the one-way latency from the iPad.

**Copy Report** puts a plain-text summary on the clipboard for sending on. To leave it
logging unattended, launch it with `-reportPath <file>`, and it rewrites the report there
every second.

One-way latency needs the two clocks' offset, which is estimated from the ping with the
shortest round trip. It is only as good as the whole milliseconds on the wire, so expect
about ±1 ms.
