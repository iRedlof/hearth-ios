# Card style on iOS

Card style is ported from the Android app (`CardStylePage.kt`, `CardStyle.kt`, `CardStyles.kt`,
`CardLook.kt`, `BeaconChrome.kt`, `WallpaperBackdrop.kt`). The Android source is the truth; this
page says what iOS has, what it leaves out, and where each piece lives.

## Owner decision (2026-11-27)

**Glass, Wallpaper and Corners are left out and not shown at all.** An iPhone widget cannot draw
them:

| Android | Why not on iOS |
|---|---|
| Background **Glass** (see-through, 40–90%) | A widget's background is opaque; iOS does not show the wallpaper behind it. |
| Background **Wallpaper** (Material You colours) | iOS gives a widget no colours from the wallpaper. |
| **Corners** Round / Soft / Square | iOS fixes every widget's corner radius. |

Everything else is the same as Android. Because Glass (Android's default) is unavailable, the iOS
default background is **Status**.

## What is ported

### The choices

| | Values | Default |
|---|---|---|
| Background | Status · Colour (Ocean, Night, Plum, Rose, Forest, Slate, Graphite, Snow) · Black | Status |
| Text size | Smaller 0.9 · Normal 1.0 · Larger 1.12 | Normal |
| Small print | on / off | on |

The summary under the "Card style" rows reads like Android's: `Status colours`, `Plum · Larger`,
`Black · Smaller · no small print`.

### How a card draws a style

**Every card is a Beacon card: a rail and a body. The style paints the BODY. The rail always
keeps the widget's state colour and its own ink** (ChargePoint keeps its orange rail). That is
Alarm, Thermostat, Car and ChargePoint, and, since the two-panel redesign (2026-11-28), Lights,
Quick actions, Favourites, Activity and Batteries. No card is a flat, whole-card style any more,
so Android's `cardLook` has no iOS counterpart.

| Background | Body | Body inks |
|---|---|---|
| Status | `#262B27` | light (`#F2F5ED`) |
| Colour | the colour's vertical two-stop gradient, a sheen across the top 96pt (`#38FFFFFF` → `#12FFFFFF` → clear), a 1pt `#1FFFFFFF` stroke | light |
| Snow | the light Beacon body (`#FEFCF4` → `#F2F1E6` → `#DFE5D9`) | dark (`#26342C`) |
| Black | `#000000` under Android's body glaze | light |

Chips, the Disarm pill, setpoint colours, the locked/unlocked door colour and Sentry-on follow the
body (light or dark), with Android's values. The Alarm card's Garage row takes the body's fill,
inks and text size exactly as the front-door row does (closed is the locked colour, open the
unlocked one).

**The two-panel widgets (Lights, Quick actions, Favourites, Activity, Batteries)** draw their
tiles, chips and rows with the same body tokens: a tile that is on or an action that can run is a
flat chip, anything off or unavailable a faint one; the "on" glyph and a low battery take the heat
setpoint's amber, a nearly empty battery the alert red. Their rail takes one of three existing
tones (`DoorsTone`): warm when something is on or wants attention, calm when all is fine, neutral
when not set up or unreachable (Activity is always neutral). See "Two-panel widgets" below.

**Text size** multiplies every text in the card (the rail's and tiles' glyphs keep their size, as
on Android). The two-panel widgets do not plan rows in points: each offers `ViewThatFits` its
layouts from fullest to barest, so a larger text size shows fewer tiles or rows rather than
overflowing. The Alarm card's two door rows (front door + garage) lower their own text only as far
as needed to fit the medium widget (`alarmDoorRowsLayout`).

**Small print off** hides what Android hides: the "Checked …" stamp (every card) and
ChargePoint's context lines under the rail's answer. Android also hides Activity's "by …" and
Quick's last-run line; the iOS cards show neither.

### Two-panel widgets

Lights, Quick actions, Favourites, Activity and Batteries share one anatomy and one size (medium):

| | Rail (the answer) | Body |
|---|---|---|
| Lights | "3 on" / "All off" over "of 3 lights" | up to four tiles that toggle |
| Quick actions | "4 actions" over "Tap to run" | up to four chips that run a script |
| Favourites | "2 on" / "All off" over "of 4" | up to four tiles that toggle or run |
| Activity | the latest event: what, then what happened and when | the three events before it |
| Batteries | "All good" over "4 tracked", or "2 low" over what is low | the three lowest |

What is left out is counted: "+N more". Not set up is "Set up" over "Tap to connect" on the rail
and "Connect Home Assistant" with Connect in the body. Unreachable is a neutral rail ("3 not
reporting", "Can't run" over "Home is unreachable", or the last-known answer), a "Can't reach Home
Assistant" line, and the last-known items: lights, favourites and actions as Unavailable and not
tappable, batteries and events with the values last read.

Everything a rail says, its tone, what a body shows and how many items fit is decided in
`HearthKit/Sources/HearthKit/Panels/` and tested there; `Shared/Panels/` only draws it. Both
halves are pinned to the widget's height, so content gives way instead of overflowing: fewer
tiles or rows first, the rail's glyph and answer smaller before a line of detail is dropped.

### The page

Home → Look → **Card style** (subtitle: the live summary) edits All cards. A widget's page → Look →
**Card style** (subtitle: `Follows All cards` / `Its own: <summary>`) edits that widget.

Top to bottom, as on Android: the preview (the added widget drawn for real with its current data,
on a dusk wallpaper backdrop; on All cards a ‹ name › stepper walks the added widgets; none added:
"Add a widget to see it here") · per widget only, "This card uses": Same as all cards | Just this
card (it opens on Just this card, so editing never restyles every card) · Background (three tiles,
and eight round swatches under Colour) · Text size · Small print. There is no Reset: every change
saves at once and reloads the widgets.

### Differences that remain

- **Own style is per widget kind, not per placed widget.** Android keys it by `appWidgetId`;
  WidgetKit's static widgets have no per-placement identity.
- **One size per widget, and it is medium.** The small sizes (Alarm, Thermostat, Car) and the
  small-only Glance widget were removed (owner decision 2026-11-27); Lights, Favourites and
  Activity went from large to medium with the two-panel redesign. There is nothing unstyled left.

## Where it lives

| What | Where |
|---|---|
| The model, every colour and every decision (pure, tested) | `HearthKit/Sources/HearthKit/CardStyle/` |
| Storage (App Group; keys `cardStyleGlobal`, `cardStyleOverrides`) | `Shared/CardStyleStore.swift` |
| The style reaching a view (`\.cardStyle` environment) | `Shared/CardStyleEnvironment.swift` |
| Drawing a styled background | `Shared/CardSurfaceView.swift` |
| The two-panel widgets: decisions / drawing | `HearthKit/Sources/HearthKit/Panels/` / `Shared/Panels/` |
| Every widget reading its style | `HearthWidgets/CardStyledContent.swift`, used by each widget in `HearthWidgetBundle.swift` |
| The page | `Hearth/Widgets/CardStylePage.swift`, `CardStyleControls.swift`, `CardStylePreview.swift` |

Styles saved by the first iOS port still load: its `byState` background decodes as Status. An own
style saved for a removed widget (Glance, Doors) is dropped when the stored styles are read
(`cardStyleOverrides(fromStored:)`).

## Checking a style without an account (DEBUG builds)

`-parityCardStyle <value>` makes every `-parityState <id>` fixture draw in that style:

```
<background>[;text=<smaller|normal|larger>][;small=<on|off>]
```

`<background>` is `status`, `black`, or `colour:<ocean|night|plum|rose|forest|slate|graphite|snow>`.
Options may be separated by `;` or `,` (a comma needs no shell quoting). Examples:

```
-parityState alarm-disarmed -parityCardStyle status
-parityState car-parked -parityCardStyle colour:plum
-parityState thermostat-auto -parityCardStyle colour:snow,text=larger,small=off
-parityState lights-failed -parityCardStyle colour:snow
```

The two-panel fixtures are `lights-`, `quick-`, `favourites-`, `activity-` and `battery-` followed
by a state: `ready` (`battery-good`), a second state (`lights-off`, `favourites-off`,
`quick-unavailable`, `activity-empty`, `battery-low`), `overflow`, `long_names`, `setup`, `failed`.

Without the argument, or with a value that does not parse, fixtures draw in the default style.
With `-parityWidgetKit` the same style reaches the fixture drawn inside the real widget.
