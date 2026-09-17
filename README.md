# Remote (remotebontrol)

A free Samsung TV remote for iPhone. No subscription, no ads, no account, nothing leaves your Wi-Fi.

Built because the "Universal TV Remote" app kept charging $2.99 a week for a WebSocket call the TV answers for free.

## How it works

- **Discovery**: sweeps the phone's /24 for `http://<ip>:8001/api/v2/` (Samsung Tizen answers with name, model, MAC). No multicast entitlement needed, and it catches TVs that ignore ping.
- **Control**: `wss://<ip>:8002/api/v2/channels/samsung.remote.control?name=<base64>&token=<token>`. The first connection makes the TV show an Allow prompt; the token it returns is stored and reused.
- **Apps**: `POST http://<ip>:8001/api/v2/applications/<appId>` launches Netflix / YouTube / etc. without pairing.
- **Power on**: Wake-on-LAN magic packet to the TV's MAC (unicast to last IP + subnet broadcast). Power off is `KEY_POWER`.

Verified 2026-09-17 against a Samsung Q80T (QN65Q80TAFXZA, Tizen 5.5) and the API surface of a Q6 (2018) and CU8000 (2023).

## Layout

- `ios/` — SwiftUI app, XcodeGen `project.yml` is the source of truth.
- `tools/` — App Store Connect helpers (metadata, screenshots, submit) sharing `asc_common.py`.
- `web/` — landing + privacy policy for GitHub Pages.

## CI

`.github/workflows/ios.yml`: unsigned compile → simulator screenshots (demo mode `REMOTE_DEMO=1`, `-tab remote|keypad|apps`) → cloud-signed archive to TestFlight. Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`.
