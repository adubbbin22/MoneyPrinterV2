# Getting to TestFlight

Status: **not ready**. The code is written and the signal pipeline is
validated, but no build artifact has ever been produced. This is what stands
between here and a build testers can install, in the order it blocks.

## 1. Produce a build at all

- [ ] **Generate the Xcode project.** `brew install xcodegen && xcodegen generate`.
      `Package.swift` only declares the two library targets; the app target
      comes from `project.yml`.
- [ ] **Compile it.** The Swift has never been through a compiler — it was
      written in a Linux container with no toolchain and no route to install
      one. Run `swift test` first to exercise the two library modules, then
      build the app target. Expect an ordinary first-build error wave.
- [ ] **App icon.** `App/Resources/Assets.xcassets` does not exist yet. App
      Store Connect rejects any upload without a 1024×1024 icon, and it fails
      at processing time rather than at build time.
- [ ] **Launch background colour.** `project.yml` references a
      `LaunchBackground` colour asset that needs creating alongside the icon.
- [ ] **Signing.** Team ID, a real bundle identifier, and a provisioning
      profile carrying the HealthKit and CloudKit entitlements.
- [ ] **CloudKit container.** `iCloud.com.pulselog.app` has to exist in the
      developer portal, or SwiftData falls back to local-only storage (which
      the app handles, but sync silently will not work).

## 2. Things that will be broken in a tester's hands

- [ ] **StoreKit products.** `com.pulselog.plus.monthly` and `.annual` must
      exist in App Store Connect. Until they do, `Product.products(for:)`
      returns an empty array and the paywall renders with no purchase buttons.
      `App/Resources/PulseLog.storekit` makes it testable locally in the
      meantime — set it as the StoreKit configuration in the scheme.
- [ ] **A real device.** Camera PPG cannot work in the simulator; there is no
      camera and no torch. Every measurement path needs device testing.
- [ ] **Paid tier gating.** `SubscriptionStore.isSubscribed` has never been
      exercised against real transactions, including the container rebuild on
      entitlement change.

## 3. Before anyone else's heart rate depends on it

- [ ] **Hardware validation.** This is the real gate. The estimator is
      validated against synthetic signals of known rate — 0.55 BPM mean error
      under nominal conditions, and a confidence gate with no accepted reading
      off by more than 10% of the true rate. None of that establishes that the
      *system* works: it says nothing about this camera, this torch level, this
      skin tone, or this person's perfusion.

      Before shipping to testers, measure at least 20 people against a chest
      strap or pulse oximeter, across varied skin tones, ages and hand
      temperatures, at rest and after exertion. Compare Bland-Altman, not just
      a mean error. If the gate rejects too much on real hands, the threshold
      is tuned against synthetic data and needs re-deriving from real captures.

      Skipping this means shipping confident numbers of unknown accuracy, which
      is the exact failure this app was built to avoid.

- [ ] **Thermal behaviour.** The torch runs at 0.3 to limit heating, but that
      was reasoned about, not measured. Check sustained measurements on an
      older device and watch for exposure drift as the module warms.

## 4. App Store Connect paperwork

- [ ] **Privacy nutrition labels.** Health and fitness data, not linked to
      identity, not used for tracking. Must match
      `App/Resources/PrivacyInfo.xcprivacy`.
- [ ] **Export compliance** is pre-answered via `ITSAppUsesNonExemptEncryption`
      in `project.yml`, so upload will not prompt.
- [ ] **Beta App Review** — required for external testers, not for internal
      ones (up to 100 team members). Health apps draw attention here. The
      honest positioning helps: the app never claims to measure blood pressure,
      and states it is not a medical device during onboarding.
- [ ] **Support URL and a privacy policy URL.** Both required.

## What internal testing needs, minimally

Items 1 and 2, plus a device. Internal TestFlight skips Beta App Review, so a
signed build with an icon can go to your own team as soon as it compiles —
but do not send it to anyone who might believe the numbers until item 3 is
done.
