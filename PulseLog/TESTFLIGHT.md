# Shipping PulseLog to TestFlight

Everything that can be automated is. What remains needs a Mac, an Apple
Developer account, and decisions only the account holder can make.

## What is done

- App icon (1024×1024, no alpha — regenerate with `python tools/make_icon.py`)
- Launch background colour asset
- `project.yml` — generates the Xcode project, app target, Info.plist
- Entitlements (HealthKit, CloudKit) and the privacy manifest
- Local StoreKit configuration so the paywall works before products exist
- `fastlane/Fastfile` — test, build, upload, with automatic build numbering
- `.github/workflows/pulselog-testflight.yml` — the same, on a macOS runner

## What you have to do

### 1. Apple side (once)

1. **Apple Developer Program** membership, if you don't have one ($99/year).
2. **App ID** in the developer portal for `com.pulselog.app` (or your own —
   set `PULSELOG_BUNDLE_ID` if it differs). Enable **HealthKit** and **iCloud**
   capabilities on it.
3. **CloudKit container** `iCloud.com.pulselog.app`. Without it SwiftData falls
   back to local-only storage; the app handles that, but sync won't work.
4. **App record** in App Store Connect. Category: Health & Fitness.
5. **App Store Connect API key** — Users and Access → Integrations → Keys →
   App Manager role. Download the `.p8` once; it cannot be re-downloaded.

### 2. Local secrets

```bash
cd PulseLog
cat > .env <<'ENV'
ASC_KEY_ID=XXXXXXXXXX
ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
ASC_KEY_CONTENT=<base64 of AuthKey_XXXXXXXXXX.p8>
PULSELOG_TEAM_ID=XXXXXXXXXX
ENV
```

`.env` is gitignored. Encode the key with
`base64 -i AuthKey_XXXXXXXXXX.p8 | pbcopy`.

For CI, set the same values as repository secrets, plus `MATCH_*` if you use
fastlane match for certificates.

### 3. First build

```bash
cd PulseLog
brew install xcodegen
bundle install
swift test            # library suites first — no signing needed
xcodegen generate
open PulseLog.xcodeproj
```

**Expect compile errors on this first build.** The Swift has never been
through a compiler; it was written in a Linux container with no toolchain
available. `swift test` exercises the signal and domain modules, which is
where a silent defect would actually matter — get that green before touching
the app target.

Then run on a physical device. Camera PPG cannot work in the simulator: there
is no camera and no torch.

### 4. Upload

```bash
bundle exec fastlane beta
```

Or run the **PulseLog TestFlight** workflow from the Actions tab.

The lane runs the tests, bumps the build number past whatever is already on
TestFlight, builds, and uploads. It distributes to **internal testers only** —
see below.

### 5. Subscriptions

Create `com.pulselog.plus.monthly` ($3.99) and `com.pulselog.plus.annual`
($19.99) in App Store Connect, in a subscription group named PulseLog Plus.
Until they exist, `Product.products(for:)` returns an empty array and the
paywall renders with no purchase buttons. Products need review before they
work in external TestFlight, though internal testers can buy in sandbox.

## Internal versus external

The lane sets `distribute_external: false` deliberately.

**Internal** (up to 100 people on your team) needs no Beta App Review. Fine for
a build whose numbers nobody is relying on — as long as testers are told the
heart rate readings are unvalidated.

**External** (up to 10,000) triggers Beta App Review, and should wait for the
validation below. Flip `distribute_external: true` when you get there.

## The thing that is not a checkbox

The estimator is validated against **synthetic signals**: 0.55 BPM mean error
under nominal conditions, and a confidence gate under which no accepted
reading is off by more than 10% of the true rate. That establishes the
algorithm is sound. It says nothing about this camera, this torch level, this
skin tone, or this person's perfusion.

Before external distribution:

- At least 20 people, measured against a chest strap or pulse oximeter
- Varied skin tones, ages, and hand temperatures — melanin absorbs at the
  wavelengths this depends on, and cold hands are the dominant real failure
- At rest and after exertion, to cover the range
- Compare with a Bland-Altman plot, not just a mean error: the question is
  whether the error is consistent, not whether it averages out
- Check the rejection rate on real hands. If the gate rejects too much, the
  0.45 threshold is tuned to synthetic data and needs re-deriving from real
  captures

Skipping this means shipping confident numbers of unknown accuracy, which is
the failure this app was built to avoid.

Also worth measuring rather than assuming: the torch runs at 0.3 to limit
heating, but that figure was reasoned about, not tested. Watch for exposure
drift across back-to-back measurements on an older device.

## App Store Connect paperwork

- **Privacy nutrition labels** — health and fitness data, not linked to
  identity, not used for tracking. Must agree with `PrivacyInfo.xcprivacy`.
- **Export compliance** is pre-answered via `ITSAppUsesNonExemptEncryption`,
  so upload won't prompt.
- **Support URL and privacy policy URL** are both required before external
  testing.
