# DECtalk for Apple

The classic **DECtalk** formant speech synthesizer (the "Stephen Hawking voice"),
running natively on **macOS and iOS** — both as a standalone app and as a
**system voice** for VoiceOver / Spoken Content.

Built by wrapping the [`dectalk/dectalk`](https://github.com/dectalk/dectalk) C
engine, with the Apple integration modeled on
[`tgeczy/TGSpeechBox`](https://github.com/tgeczy/TGSpeechBox).

## Architecture

```
DECtalkEngine.xcframework   ~90 dapi/src/*.c compiled static (no dlopen) + dtk_shim
        ▲                   macOS · iOS device · iOS simulator
DECtalkKit (Swift package)  DECtalkSynthesizer: text → AVAudioPCMBuffer
        ▲                        ▲
DECtalk.app (SwiftUI)   DECtalkVoice.appex (AVSpeechSynthesisProviderAudioUnit)
  macOS + iOS             registers 9 DECtalk voices as system voices
```

| Layer | Path |
|-------|------|
| Engine build script | `engine/build-xcframework.sh` (+ `sources.txt`, `patches/`) |
| C shim (clean API over `ttsapi.h`) | `Sources/CDECtalk/` |
| Swift wrapper, settings, bundled dictionary | `Sources/DECtalkKit/` |
| Standalone app (macOS + iOS) | `Apps/DECtalkApp/` |
| System-voice extension | `Apps/DECtalkVoiceExtension/` |
| Xcode project generator | `project.yml` (xcodegen) |
| Dependency bootstrap | `scripts/bootstrap.sh` |

The DECtalk engine sources, the compiled `DECtalkEngine.xcframework`, and the
`.dic` dictionary are **not** committed (proprietary + large). `bootstrap.sh`
fetches and builds them.

## Getting started

```sh
git clone <this repo> && cd DECTalkApple
./scripts/bootstrap.sh      # clones the engine, builds the xcframework,
                            # installs the dictionary, generates DECtalk.xcodeproj
swift test                  # engine + kit tests (renders real, non-silent audio)
open DECtalk.xcodeproj      # build/run the apps
```

To sign for a device, set your Apple **Team ID** in `project.yml`
(`DEVELOPMENT_TEAM`) and re-run `xcodegen generate`.

### Install to a connected iPhone (CLI)

```sh
DEVICE=$(xcrun devicectl list devices | awk '/iPhone/ && /available/ {print $3; exit}')
xcodebuild -project DECtalk.xcodeproj -scheme DECtalkApp-iOS -configuration Debug \
  -destination "id=<device-udid>" -derivedDataPath build/dev -allowProvisioningUpdates build
xcrun devicectl device install app --device "$DEVICE" \
  build/dev/Build/Products/Debug-iphoneos/DECtalk.app
```

## Using the system voice (macOS)

Third-party speech providers are only picked up from an **installed** app:

```sh
cp -R "$(xcodebuild -project DECtalk.xcodeproj -scheme DECtalkApp-macOS \
        -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR /{print $3}')/DECtalk.app" /Applications/
open /Applications/DECtalk.app       # registers the extension
```

The nine voices (Perfect Paul, Beautiful Betty, Huge Harry, …) then appear in
**System Settings → Accessibility → Spoken Content → System Voice** (macOS) or
**Settings → Accessibility → Spoken Content / VoiceOver** (iOS).

## Settings

Full DECtalk parameter control, driven by inline commands, **shared between the
app and the system voice** via an App Group (the extension reads the settings the
app writes):

- **Global (all voices):** Rate `[:rate]`, Volume `[:vo set]`, SPF `[:spf]`,
  Sentence pause `[:pp]`, Comma pause `[:cp]`, and a "Honor VoiceOver pauses" toggle.
- **Per-voice `[:dv]` parameters** (28, each speaker customizable): pitch, pitch
  range, assertiveness, head size, smoothness, richness, breathiness, formants,
  source gains, and more. Any left on "auto" keep the voice's built-in value.

### VoiceOver pauses

The extension converts VoiceOver's SSML `<break>` elements into **real inserted
silence** at the break position (DECtalk's `[:slnc]`/`[_<N>]` don't work — they're
spoken aloud; that syntax is Apple's Speech Manager, not DECtalk). Pauses land in
multi-part announcements and continuous reading. Pauses *between single items while
swiping* aren't possible for any provider — VoiceOver cancels the utterance the
instant you swipe.

## Downloads

Every push builds the apps and uploads them as workflow **artifacts**; every
`v*` **tag** publishes a **[Release](../../releases)** with permanent downloads:

- **`DECtalk-iOS-unsigned.ipa`** — install with **Sideloadly** or **AltStore**,
  which re-sign it with your own Apple ID on install (no cert needed from CI).
- **`DECtalk-macOS.zip`** — unsigned `.app` (right-click → Open the first time, or
  self-sign with `codesign --force --deep --sign - DECtalk.app`).

Cut a release with:

```sh
git tag v0.1.0 && git push origin v0.1.0
```

## Signed ad-hoc distribution (iOS)

For installing on your own registered devices with a **real signature** (no
per-device re-signing by the end user), there's a local ad-hoc pipeline modeled
on OTA distribution:

```sh
source Signing/asc.env                                   # ASC key + config (gitignored)
swift scripts/asc_tool.swift register <UDID> "<name>"    # register a device (once)
echo "<device-resource-id>  <UDID>  <name>" >> Signing/.devices   # pin it
./scripts/adhoc.sh https://your-host.example/dectalk     # build → re-sign → OTA bundle
./scripts/publish.sh                                     # (optional) upload to your web server
```

`adhoc.sh` refreshes the ad-hoc provisioning profiles (app **and** the voice
extension) for the pinned devices, builds the app, **re-signs inside-out**
(nested bundle → extension → app) with your `iPhone/Apple Distribution` identity,
and writes `dist/ota/`: `DECtalk.ipa`, an itms-services `manifest.plist`, and an
`index.html` install page. Host all three over HTTPS and open the page on a
registered device to install over the air.

All signing material lives in `Signing/` and is **git-ignored** (never committed):
the ASC API key (`.p8`), the distribution profiles (`.mobileprovision`), and the
pinned device list. `scripts/asc_tool.swift` is a small App Store Connect API
client (register devices, generate profiles) — no secrets in it, so it's tracked.

This is separate from — and complements — the unsigned GitHub-release builds
above.

## Continuous integration

`.github/workflows/ci.yml` runs on macOS: bootstraps, runs `swift test`, builds
both apps **unsigned**, packages the iOS `.ipa` + macOS `.zip`, and (on tags)
attaches them to a GitHub Release. CI never needs your signing certificate — the
iOS build is unsigned and re-signed at install time by the sideloading tool.

## Notes & limits

- **License:** the upstream engine (`upstream/LICENCE`) is **proprietary FONIX**,
  provided "as is" with no distribution grant — which is why it's fetched, not
  committed. Fine for personal/experimental builds; **App Store or other
  distribution requires rights clearance.**
- **Signing:** device installs / trusted macOS system voices need a real Apple
  **Development Team** (`DEVELOPMENT_TEAM` in `project.yml`). On macOS the App
  Group is Team-ID-prefixed so it works without portal registration; on iOS
  Xcode auto-registers the `group.` form.
- Currently ships **US English** (`dtalk_us.dic`); the engine also builds UK / SP
  / GR / LA / FR dictionaries.
- Engine output is 11025 Hz mono; the extension upsamples to 22050 Hz.
