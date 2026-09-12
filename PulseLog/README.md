# PulseLog

A camera-based heart rate monitor with a blood pressure journal, for iOS 17+.

Measures pulse by fingertip photoplethysmography — the rear camera and flash
read the light absorbed by blood moving through your finger. Logs blood
pressure from a real cuff, and analyses both over time.

## The position

The App Store category this competes in is built on an ambiguity. Apps titled
"Heart Rate Monitor" carry subtitles like "Log Blood Pressure & Oxygen",
screenshots showing a finger on a camera next to a large `190/95`, and a
blood-pressure feature that is a data-entry form. Nothing is technically
claimed. Everything is implied.

PulseLog takes the opposite position, and the whole design follows from it:

- **Heart rate is measured.** Camera PPG is real, and the implementation here
  is validated to a mean error of 0.55 BPM under nominal conditions.
- **Blood pressure is entered, never measured.** No validated camera-based
  method exists. The second onboarding screen says so in as many words.
- **A reading is shown only when it can be trusted.** Below a calibrated
  confidence threshold the app asks for a retake rather than displaying a
  number.
- **A pattern is reported only when the data supports it.** Correlations carry
  confidence intervals and a ten-observation minimum. The app would rather
  show an empty state than invent a claim about someone's heart.

## Layout

```
PulseLog/
├── reference/                  Python reference implementation + validation harness
├── Sources/
│   ├── PulseLogSignal/         PPG pipeline. No Apple frameworks; testable anywhere
│   └── PulseLogCore/           Domain logic: classification, norms, statistics, insights
├── Tests/                      Vector tests against the reference, plus standalone tests
└── App/                        iOS app (requires Xcode)
    ├── Capture/                AVFoundation, exposure locking, ROI extraction
    ├── Measurement/            Capture UI, fact cards, save flow
    ├── BloodPressure/          Manual entry and classification UI
    ├── Trends/                 Charts, insights, doctor report PDF
    ├── Health/                 HealthKit read/write, reminders
    ├── Model/                  SwiftData records
    ├── Onboarding/ Paywall/    First run and subscription
    └── Shared/                 Theme, haptics
```

The two `Sources` modules deliberately depend on nothing from Apple beyond
Foundation. The parts of this app worth testing are the signal processing and
the domain logic, and neither should require a simulator to exercise.

## Building

The signal and core modules build and test standalone:

```bash
cd PulseLog
swift test
```

The app target needs an Xcode project referencing `App/` and both library
targets. It requires a physical device — camera PPG cannot work in the
simulator, which has no camera or torch.

Required `Info.plist` keys:

| key | reason |
|---|---|
| `NSCameraUsageDescription` | pulse measurement |
| `NSHealthShareUsageDescription` | reads sleep and steps to explain trends |
| `NSHealthUpdateUsageDescription` | writes readings back to Health |

Entitlements: HealthKit, and iCloud/CloudKit if sync is enabled.

## Accuracy

Validated against synthetic signals of known rate, over 30 s windows at 30 fps.
Full results in `reference/README.md`.

| scenario | MAE | p95 | max | ≤3 BPM |
|---|---|---|---|---|
| nominal | 0.55 | 1.70 | 3.37 | 99.2% |
| weak perfusion (0.25% AC/DC) | 0.60 | 1.94 | 3.65 | 97.7% |
| heavy breathing wander (8×) | 0.55 | 1.64 | 3.41 | 99.2% |
| frame jitter + 8% drops | 0.56 | 1.71 | 3.79 | 99.2% |
| 15 s window | 0.91 | 2.53 | 4.33 | 96.9% |

Adverse conditions do degrade badly, which is what the confidence gate exists
for. Pooled across 864 runs and nine scenarios, gating at 0.45 accepts 83% of
attempts, and among those accepted **no reading is off by more than about 5
BPM** — against 24 gross errors if the gate is lowered to 0.30.

**These figures are from synthetic signals, not from people.** Before shipping,
the pipeline must be validated against a reference device — a chest strap or
pulse oximeter — across at least 20 subjects at varied heart rates, skin tones
and perfusion states. Synthetic validation establishes that the algorithm is
sound; only hardware validation establishes that the *system* is.

## State

| component | status |
|---|---|
| PPG algorithm | validated numerically; 864-run sweep |
| Swift signal port | written, vector-pinned tests; **not yet compiled** |
| Domain core | written with tests; **not yet compiled** |
| App layer | written; **not yet compiled** |
| Hardware validation | **not started** — requires a device and reference instrument |

The Swift has not been compiled: it was developed in a Linux container with no
Swift toolchain and no route to install one. Expect ordinary compile errors on
first build. The test suites are the mechanism for catching anything worse —
run `swift test` first, before the app target.

## Not in this app

- Any estimate of blood pressure or SpO₂ from the camera
- A simulated ECG waveform
- The word "accurate" in user-facing copy
- Weekly subscription pricing
