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

**Beacon cards (Alarm, Thermostat, Car, ChargePoint): the style paints the BODY. The rail always
keeps the widget's state colour and its own ink** (ChargePoint keeps its orange rail).

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

**The other cards (Lights, Quick actions, Favourites, Activity, Batteries)** follow
Android's `cardLook`: Status is the card exactly as it was; a colour or black replaces the whole
card's background with white inks (dark inks on Snow). On a chosen background a card that needs
you shows it as an amber headline and a strip on the leading edge.

**Text size** multiplies every text in the card (icons keep their size, as on Android). Collection
cards (Activity, Batteries) feed the scale into their row planning, so rows still fit. The Alarm
card's two door rows (front door + garage) lower their own text only as far as needed to fit the
medium widget (`alarmDoorRowsLayout`).

**Small print off** hides what Android hides: the "Checked …" stamp (Beacon cards, Lights,
Favourites, Batteries), ChargePoint's context lines under the rail's answer, and Activity's
"by …". Android also hides Quick's last-run line; the iOS Quick card does not show one.

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
- **One size per widget.** The small sizes (Alarm, Thermostat, Car) and the small-only Glance
  widget were removed (owner decision 2026-11-27), so there is nothing unstyled left.

## Where it lives

| What | Where |
|---|---|
| The model, every colour and every decision (pure, tested) | `HearthKit/Sources/HearthKit/CardStyle/` |
| Storage (App Group; keys `cardStyleGlobal`, `cardStyleOverrides`) | `Shared/CardStyleStore.swift` |
| The style reaching a view (`\.cardStyle` environment) | `Shared/CardStyleEnvironment.swift` |
| Drawing a styled background | `Shared/CardSurfaceView.swift` |
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
```

Without the argument, or with a value that does not parse, fixtures draw in the default style.
With `-parityWidgetKit` the same style reaches the fixture drawn inside the real widget.
