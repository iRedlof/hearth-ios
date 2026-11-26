# Card Style on iOS — what WidgetKit allows

Android's per-widget **Card Style** has four axes: Background (Status / Colour / Glass / Black /
Wallpaper), Corners (Round / Soft / Square), Text size (Smaller / Normal / Larger), and a Small-print
toggle. WidgetKit constrains most of this at the OS level:

| Axis | Android | iOS / WidgetKit |
|---|---|---|
| **Corners** | Round / Soft / Square | **Not possible.** iOS gives every home-screen widget a *system-fixed* corner radius (`ContainerRelativeShape`); an app cannot change it. |
| **Background: Glass / Wallpaper** | real blur / see-through to wallpaper | **Not possible.** A widget's background is an opaque `containerBackground`; iOS does not expose the wallpaper behind it or a live-blur material for the whole card. |
| **Background: Black / Colour / Status** | solid colours | **Supported** — these are just the `containerBackground` colour each Hearth widget already sets (graphite, the tone colour, etc.). A user-chosen colour/black toggle is a small, portable addition. |
| **Text size (Smaller/Normal/Larger)** | font scale | **Supportable** — a stored scale the views multiply their point sizes by. Not yet wired (would thread a `CardStyle` through all 10 views). |
| **Small print** (hide the secondary lines) | toggle | **Supportable** — a stored bool the views read to drop the sub-lines. Not yet wired. |

## Decision

Per the project rule *"whatever is not supported, there's no point adding it"*: Corners and the
Glass/Wallpaper backgrounds are **dropped** — they are OS-controlled and cannot be matched. The two
portable axes (**Text size**, **Small print**) and a background colour/black choice are deferred as a
polish enhancement; wiring them means passing a shared `CardStyle` (App-Group stored, like `HaConfig`)
into each Beacon/non-Beacon view and scaling fonts / gating sub-lines. Say the word and I'll add them.
