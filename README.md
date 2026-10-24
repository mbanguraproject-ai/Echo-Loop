# Echo Loop

A one-thumb synthwave lane runner for Android. Swipe across three lanes of neon highway: dodge
walls and data trains, jump barriers, slide under laser gates. Your best run is recorded and
races you on the next run as a pink "echo" that replays your exact moves. Crash, and you can
rewind time a few seconds (rewarded ad or shards) to keep the run going.

Version 2.0 replaces the 1.x loop arena with this runner, keeping the look, the shop, the
riders, the purchases and the player's shard wallet (old saves migrate automatically).

Web prototype (same code): https://claude.ai/artifact/7zpBThoSuwUrs442UJfTWn

## What's in this folder

| Path | What it is |
| --- | --- |
| `game/echo-loop.html` | The whole game in one file. This is the source of truth. |
| `src/native.js` | Android bridge: AdMob rewarded + interstitial ads, Google Play Billing, haptics, back button. |
| `scripts/build-www.mjs` | Builds `www/` for the app: bundles fonts (works offline) and `native.js`. |
| `scripts/setup-android-sdk.sh` | Installs what the build needs on Linux: JDK 21 if missing, Android SDK, npm packages. |
| `.devcontainer/` | GitHub Codespaces setup: Node 22, JDK 21, Android SDK installed on first start. |
| `.github/workflows/android.yml` | GitHub Actions: debug APK on every push, signed AAB/APK when secrets are set. |
| `android/` | Capacitor 8 Android project (Gradle, compileSdk/targetSdk 36). |
| `store/` | Play listing assets: 512px icon, 1024×500 feature graphic, 8 phone screenshots, listing text. |
| `PRIVACY.md` | Privacy policy template. Fill it in and host it before you publish. |

## Build

### On GitHub (no setup needed)

Every push and pull request runs `.github/workflows/android.yml`. Open the run under the
**Actions** tab and download the APK from **Artifacts**.

- **Debug APK:** built every time. Install it on a phone to test.
- **Signed release AAB and APK:** built when the four signing secrets are set (Settings →
  Secrets and variables → Actions):
  - `ANDROID_KEYSTORE_BASE64`: run `base64 -w0 echo-loop-upload.jks` and paste the output
  - `ANDROID_KEYSTORE_PASSWORD`
  - `ANDROID_KEY_ALIAS`
  - `ANDROID_KEY_PASSWORD`

  Upload the AAB to Play Console.
- **GitHub Release:** push a version tag (`git tag v2.0.1 && git push origin v2.0.1`) and the build is
  attached to a release.

### In GitHub Codespaces

Open the repo in a codespace (Code → Codespaces → Create). `.devcontainer/` gives it Node 22 and
JDK 21 and installs the Android SDK on first start. Then, in the terminal:

```bash
npm run apk       # builds EchoLoop-debug.apk in the project folder
```

In the Explorer, long-press or right-click `EchoLoop-debug.apk` and choose **Download**.
For a codespace created before `.devcontainer/` existed, run `npm run setup` once first.

### On your machine

You need Node 22+ and the Android SDK. On Linux, one command installs everything (re-running it is
safe). If your Java is older than 21, it also installs JDK 21 into `~/jdk-21` for Gradle:

```bash
npm run setup     # JDK 21 if needed + Android SDK (platform 36, build-tools 36) + npm ci
npm run apk       # debug APK -> EchoLoop-debug.apk
```

On macOS or Windows, install Android Studio instead, then run `npm install` and `npm run apk`, or
run `npm run sync` and open `android/` in Android Studio.

On hosts that Maven Central rate-limits (some cloud sandboxes), run
`bash scripts/setup-android-sdk.sh --maven-mirror` to route downloads through Google's mirror.

| Command | What it does |
| --- | --- |
| `npm run setup` | One-time machine setup (Linux, Codespaces). |
| `npm run build` | Builds `www/` from `game/echo-loop.html` (bundles fonts and `native.js`). |
| `npm run sync` | `build`, then copies `www/` into the Android project. |
| `npm run apk` | Debug APK for testing → `EchoLoop-debug.apk`. |
| `npm run apk:release` | Signed release APK → `EchoLoop-release.apk` (needs `android/keystore.properties`). |
| `npm run bundle` | Signed release AAB for Play → `EchoLoop-release.aab` (needs `android/keystore.properties`). |
| `npm run serve` | Plays the game in a browser at http://localhost:8080. It keeps running until you press Ctrl+C, so run it last or in a second terminal. |

In a browser, ads and purchases are simulated with on-screen placeholders.

## Before you publish: checklist

1. **Package name.** The app ID is `game.devbangs.echoloop`. It can never change once
   published. It is set in `capacitor.config.json` (`appId`), `android/app/build.gradle`
   (`namespace`, `applicationId`), `android/app/src/main/res/values/strings.xml` and the
   `MainActivity.java` package.
2. **AdMob.** Create the app and two ad units (Rewarded, Interstitial) at admob.google.com.
   - App ID goes in `android/app/src/main/res/values/strings.xml` (`admob_app_id`).
   - Unit IDs go in `src/native.js` (`AD_UNITS`); set `TESTING = false`.
   - In AdMob, open Privacy & messaging and create a GDPR consent message. The app already
     requests consent before loading ads.
   - Publish an `app-ads.txt` file on the website you list in Play Console.
   - The current values are Google's public test IDs, so the debug APK shows test ads.
3. **In-app products.** Play Console → Monetize → Products → In-app products. The IDs must
   match exactly (prices are suggestions; the shop shows Play's localized price automatically):

   | Product ID | Type | Suggested price | Grants |
   | --- | --- | --- | --- |
   | `starter` | one-time | $3.99 | Remove ads + Aurum skin + 1,500 shards |
   | `no_ads` | one-time | $2.99 | No interstitial ads |
   | `skin_aurum` | one-time | $0.99 | Aurum skin |
   | `skin_spectrum` | one-time | $1.99 | Spectrum skin |
   | `shards_s` | consumable | $0.99 | 1,200 shards |

   Play only lets you create products after you've uploaded a build that includes the billing
   permission, so upload to Internal testing first.
4. **Signing.** Create an upload key once and keep it safe (Play App Signing holds the real key):

   ```bash
   keytool -genkeypair -v -keystore echo-loop-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```

   Then create `android/keystore.properties` (never commit it):

   ```properties
   storeFile=/absolute/path/to/echo-loop-upload.jks
   storePassword=YOUR_STORE_PASSWORD
   keyAlias=upload
   keyPassword=YOUR_KEY_PASSWORD
   ```

   `npm run bundle` then writes the signed `android/app/build/outputs/bundle/release/app-release.aab`.
5. **Version.** Bump `versionCode` (and `versionName`) in `android/app/build.gradle` for every upload.
6. **Privacy policy.** Fill in `PRIVACY.md`, host it (GitHub Pages works), and add the URL in Play Console.
7. **Play Console forms.**
   - Ads: "Yes, my app contains ads".
   - Data safety: declare what the Google Mobile Ads SDK collects (device or other IDs,
     approximate location from IP, app interactions, diagnostics), shared for advertising and
     analytics. Google publishes the exact answers in its "Google Mobile Ads SDK data disclosure" page.
     The game itself stores progress only on the device.
   - Target audience: 13+ (choosing under-13 brings in the Families policy and child-directed ad settings).
   - Content rating: complete the IARC questionnaire (no violence, no user content, no gambling).
8. **Testing track.** New personal developer accounts must run a closed test with at least 12
   opted-in testers for 14 days before they can apply for production. Check Play Console for the current rule.
9. **Server-side receipt checks (recommended).** `src/native.js` finishes purchases on the device.
   For real money at scale, add receipt validation (for example the plugin's `store.validator` with a backend, or RevenueCat).

## How it makes money (already built in)

- **Rewarded ads, always the player's choice:**
  - **Rewind** after a crash (the biggest one: players will watch to save a long run). One rewind
    per run can be paid with an ad; the others cost shards (100, then doubling).
  - **Boost start:** fly the first 300 m before the run begins.
  - **Double the shards** after a run, **double the daily reward**, and 5 free shard videos a day in the shop.
- **Interstitials, kept gentle:** at most one every 3 runs, never in the first 3 runs, never right after
  the player chose to watch a rewarded ad, never for No Ads owners.
- **Purchases:** Starter Pack, Remove Ads, a shard pack and two premium riders. Shards also buy five
  riders, upgrades, rewinds and boost starts, so the shard pack has real uses.

## Retention hooks (already built in)

- **The echo:** your best Endless run (and today's best Daily Run) is recorded on its own clock and
  races you lane for lane. A "BEST" gate on the road marks where you have to beat it, with a
  "NEW BEST: YOU OUTRAN YOUR ECHO" moment when you pass it.
- **Score multiplier:** three missions at a time; finish all three to raise your multiplier for good
  (up to ×30). Missions scale up as the multiplier grows.
- **Upgrades:** power-up durations (magnet, shield, double shards, hyperboost) and a head start.
- **Daily Run:** a fixed track for the day with one rotating rule (Shard Rush, Laser Storm, Rail Day,
  Overdrive, Low Gravity, Blackout, Magnetic) and a first-run bonus.
- **Zones:** the scenery changes every 1,000 m (Neon Grid → Solar Drift → Void Rift), so there is
  always a next zone to reach.
- Daily streak calendar (25 → 300 shards on day 7) shown on first open each day.
- First-run tutorial: time slows before each new obstacle until the player makes the right move.
- The music builds up as you run and goes harder at top speed.

## Tuning

All the numbers live at the top of the game script in `game/echo-loop.html`: speed (`V0`, `VMAX`,
`ACCEL`), jump and slide (`JUMP_V`, `GRAV`, `SLIDE_T`), lane switch speed (`LANE_V`), the obstacle
rows table (`ROWS`, with the distance tier each row unlocks at and its weight), `REVIVE_BASE`,
`BOOST_START_COST`, `STREAK_REWARDS`, the `LAB` upgrade costs, rider prices, mission tiers and
`DAILY_MODS`. The row spacing in `genRow()` shrinks from 1.2 s to 0.62 s of travel time over the first
2,600 m. The generator checks every row against the previous one, so there is always a lane the rider
can reach in time.

Simulated play: a bot with perfect reflexes and a simple lookahead reaches a median of about 2,000 m
(range 100 to 8,000+). Expect real players to land between 300 and 1,500 m early on. Shards come in at
roughly 70 per 1,000 m without a magnet.

## What to measure in a test release

Add analytics before a wide release (Firebase Analytics is the usual choice). Log `run_start`,
`run_end` (distance, cause), `rewind` (ad or shards), `boost_start`, `ad_reward` (placement), `purchase`.
Typical targets for a casual runner: Day-1 retention of 35% or more, Day-7 of 10% or more, and 20% or
more of daily players choosing a rewarded ad. If most first runs end before 300 m, raise the starting
gap in `genRow()` or lower `V0`.
