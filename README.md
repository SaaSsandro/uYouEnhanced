# YouTubeBuilder

Build pipeline that injects a **selectable set of YouTube tweaks** into a decrypted
YouTube IPA and produces a SideStore/AltStore-compatible `.ipa`.

This repository ships no tweak sources of its own. It orchestrates third-party
tweaks — compiled from git submodules or downloaded as prebuilt packages — and
injects them into a YouTube IPA with [Theos](https://theos.dev) and
[theos-jailed](https://github.com/qnblackcat/theos-jailed).

## How a build works

1. The workflow downloads the decrypted YouTube IPA given as `decrypted_youtube_url`
   and reads its version from `Payload/YouTube.app/Info.plist`.
2. `Tools/check-inject-budget.py` verifies that the selected tweaks fit into the
   binary's load-command area. Without that check `insert_dylib` stalls for hours
   instead of failing.
3. Theos builds the submodule tweaks and theos-jailed injects every selected dylib
   — plus its settings bundle, embedded libraries and frameworks — into the app.
4. `cyan` injects the Open in YouTube Safari extension, the IPA is stripped of
   unresignable extensions and `SC_Info`, alternate app icons are registered, and
   the result is uploaded as artifact and/or draft release.

## Tweak selection

`Makefile` is the single source of truth for the tweak registry. The GitHub
workflow, the local web UI in `web/` and the YouTubeBuilder iOS app all read it
from there, so adding a tweak means editing the Makefile only.

| Variable | Meaning |
|---|---|
| `TWEAK_REGISTRY` | Tweaks compiled from a submodule (`<id>_SUBPROJECT`, `<id>_DYLIB`). |
| `PAYLOAD_TWEAKS` | Tweaks shipped as prebuilt `.deb` packages that the build downloads and unpacks. |
| `DEFAULT_TWEAKS` | Pre-selected set; also the default of the workflow's `enabled_tweaks` input. |
| `ENABLED_TWEAKS` | Space- or comma-separated ids to inject. Overrides `DEFAULT_TWEAKS`. |

Payload tweaks are listed first, because they carry most of the functionality:

```sh
make package IPA=Payload/YouTube.app ENABLED_TWEAKS="YTPlus Gonerino YouSlider"
```

## Build inputs

| Input | Default | Meaning |
|---|---|---|
| `sdk_version` | `26.5` | iOS SDK used for the Theos build. |
| `ytplus_version` | `6.0` | YTPlus payload version. |
| `ipa_prefix` | `YTPlus` | Prefix of the produced IPA file name. |
| `decrypted_youtube_url` | – | Direct URL of the decrypted YouTube IPA. |
| `bundle_id` | `com.google.ios.youtube` | Bundle ID of the produced app. |
| `app_name` | `YouTube` | Display name of the produced app. |
| `commit_id` | – | Optional commit to build at. |
| `upload_artifact` | `false` | Upload the IPA as a workflow artifact. |
| `create_release` | `true` | Create a draft release with the IPA. |
| `enabled_tweaks` | `DEFAULT_TWEAKS` | Tweaks to inject. |

## Local build

Requires Theos with an iPhoneOS SDK, `make`, `curl`, `unzip`, `ldid`, `dpkg` and a
decrypted YouTube IPA unpacked into `Payload/`.

```sh
export THEOS=$HOME/theos
make package THEOS_PACKAGE_SCHEME=rootless IPA=Payload/YouTube.app FINALPACKAGE=1 \
  SDK_VERSION=26.5 YTPLUS_VERSION=6.0 ENABLED_TWEAKS="YTPlus Gonerino"
```

`web/server.js` serves a small local front-end that reads the workflow inputs and
the tweak registry from this repository, can dispatch the GitHub workflow, and can
emit an equivalent local build script:

```sh
cd web && npm start   # http://localhost:8787
```

## The iOS app

`YouTubeBuilder` (a separate Xcode project) is a thin client for the workflow: it
dispatches it with the inputs above, shows status and logs, and downloads the
resulting IPA into its library, from where it can be handed to SideStore.

## Credits

The tweaks under `Tweaks/` are third-party projects, each under its own license —
see the respective submodule. The build pipeline descends from
[uYouPlus](https://github.com/qnblackcat/uYouPlus) /
[uYouEnhanced](https://github.com/arichornlover/uYouEnhanced) by **qnblackcat** and
**arichornlover**; their credits are kept in `control`.

There is currently no `LICENSE` file in this repository.
