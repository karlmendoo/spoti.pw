# Redesigned presentation and validation

This change is presentation-only on the existing iOS 26 Redesigned mode. Native, Shared, Core,
App, preference keys, lyric providers, playback services and migrations are unchanged.
Spotify still supplies the content, the measured row/header heights, the controllers and all
actions. Nothing creates editorial titles or rebuilds Spotify's data sources.

## Foundation

`Kit/SGRTokens` owns 4/8/12/16/20/24/32 spacing, semantic navigation/hero/section/content/player
type roles, continuous artwork corners, 12-point primary controls, 18-point mini player corners,
28-point system sheets, 0.2-second touch feedback and 0.36-second layout springs. New installs
use rose; existing accent selections (including explicit Spotify green) retain their values.
Glass belongs to navigation and floating controls. Search categories are ordinary muted colour
surfaces. Content rows have no new cards or blur. The artwork field remains dark enough for
white content, and the moving player's luminance ceiling is lower for secondary text.

## Components and screens

- `SGRHeroArtwork` replaces the duplicated full-bleed album/playlist artwork presentation with
  centered, uncropped release covers, a quiet missing-artwork placeholder and image crossfades.
  It is decorative and cannot block touches. The page's existing field borrows the cover's colour.
- `SGRHeaderInfo` puts description before actions, uses a stronger title and a width-constrained
  action row. Artist titles align with their cinematic full-bleed photo. The creator still opens
  Spotify's original profile/artist/collaborator action, including through VoiceOver.
- `SGRContentStyle` centralizes measured text, artwork, pixel separators and system sheet chrome.
  Spotify's label slots bound font sizes; original attributed colours/links, playing states and
  marquee/navigation behavior remain. Home cards/shortcuts, Library and entity rows share it.
- `SGRContentRows` applies the same type to recognized Encore song rows in other surfaces,
  including compatible search/queue rows. The walk is bounded, successful references are weakly
  cached and cleared on reuse, and unknown content is left alone. It owns no row actions.
- `SearchInput` gives UIKit search bars and explicit Search-key text fields a consistent dark
  field, readable placeholder, semantic type and accent cursor, preserving the editing delegate.
- The system tab bar has quiet selected/unselected colours, SF Symbols for recognized standard
  icons and accessible names even with labels hidden. Custom icons/order and Home hold still work.
- Mini player artwork has release-cover corners. Its progress track derives its width from the
  actual title/control frames instead of 226 hard-coded points. Spotify owns the progress fill.
  The existing player morph interpolates the new thumbnail corners without another animator.
- Now Playing has larger paused artwork, clearer semantic metadata/timestamps, more prominent
  play/pause and a quieter Fluid field. Scrubbing, buffering, Canvas, cover gestures and remote
  playback remain in their original implementations.
- Lyrics retain all timing, overlapping vocals, pronunciation, translation, meanings and sources.
  Manual browsing has a six-second hold and a native Follow Lyrics button. VoiceOver browsing
  never auto-resumes. Motion/blur reduce under accessibility settings; text scales up to 42 points.
  A weak display-link target breaks the view/clock retain cycle without changing the 80–120 Hz
  range or the existing suspension during player transitions/backgrounding.
- `SGRSettings` gives the mod's automatic-height grouped rows system-sized text and plain native
  switches. The original actions, toggles, locked flags, info buttons and preference writes remain.
  Context menu contents remain Spotify's: market/account actions cannot safely be reconstructed
  from the opaque Swift item factories. Existing sheets retain their detents and navigation.

## Performance and boundaries

Palette requests run on the existing serial queue and share a 64-entry/8 MB pressure-evictable
cache keyed by image identity, output geometry, options and contrast. Keys do not retain original
images and do not collide when addresses are reused. Search adds no per-card effect views.
Decorative artwork does not install timers, observers or display links. Shared haptics still
honour the user's switches; there is no second feedback generator on forwarded actions.

All Logos constructors are gated by `SGRedesignedUI()`. Existing Spotify hook classes/selectors
are retained; the new settings hook targets the repository's own `SGModPage`, and the generic row
hook uses UIKit cells and already-recorded Encore identifiers. These identifiers, the existing
Spotify controllers, icon names and the existing morph progress hook remain version-sensitive.
Spotify 9.1.78 is the supported test target. No new private Spotify selector is introduced.

## Builds

The existing IPA workflow still accepts the user's IPA URL and emits `spoti.ipa`. Its first
checkout now builds the selected fork/ref instead of the upstream `v0.50.0` tag, which previously
ignored all fork changes. Tool setup, sensitive-input masking, version override and uploads stay.
Dispatch it on the redesign branch. A branch push alone does not start this manual IPA workflow.

`Redesigned UI checks` separately compiles seven existing simulator harnesses. Where an iOS 26
iPhone simulator is installed, it captures eight portrait screenshots under the
`redesigned-ui-checks` artifact. A runner without that runtime reports a compile-only check.
These mocks do not prove Spotify's live element framework, network responses or device timing.

On a Mac: `THEOS=~/theos bash scripts/check-redesigned-ui.sh`. On any compatible shell:
`bash scripts/check-layers.sh`. Theos compiles every new source through its existing source glob.

## Required real-device QA

This is an implemented redesign, not a claim that hardware QA has passed. Before treating it as
production-verified, test the following on an iOS 26 iPhone with Spotify 9.1.78:

| Area | Required checks |
|---|---|
| Home | Existing shelves and recommendations, shortcuts, loading artwork, fast scrolling and taps |
| Search | Browse, keyboard, recents, typing/cancelling, song/artist/album/playlist/profile results |
| Library | All filters, Downloads, recents, create, folders, search, list/grid and empty sections |
| Playlist | Own/other/mix/Liked Songs, late Save, Sort/Mix menu, description, long title, long list, collapse/pull |
| Album/artist | Late artwork, artist/creator navigation, long names, Follow/Save/download and collapse |
| Player | Playback/queue/devices, scrubbing, rapid skips, buffering, Canvas, artwork, volume, repeated open/close |
| Lyrics | Timed/untimed/word/duet/RTL/translation/pronunciation, manual follow, meanings, no lyrics and late providers |
| Settings/sheets | Every switch/action, info/locked flags, restart behavior, detents, destructive actions |
| Accessibility | VoiceOver actions, Dynamic Type, Increase Contrast, Reduce Motion/Transparency and light system appearance |
| Geometry | Small/home-button phones, portrait/landscape player and lyrics, safe areas, keyboard, bottom content |
| Stability | Offline/network failures, repeated navigation, memory, animations and 120 Hz frame pacing |
| Native regression | Relaunch with Redesigned off; compare appearance, preferences, playback and shared features |

Spotify's existing recommendation order, search grouping, Library filters, navigation transitions,
queue reordering, and unsupported loading/empty/error surfaces remain owned by Spotify. A further
structural redesign of those opaque surfaces requires recorded device trees and action/state
verification; this change does not fabricate replacement data or hide their required functionality.
