# PPG reference implementation

The numerically-validated reference for PulseLog's heart-rate estimation, and
the source of the test vectors the Swift implementation is checked against.

It exists because the signal pipeline is the one part of this app that cannot
be evaluated by looking at it. A plausible-looking PPG implementation that is
quietly wrong produces confident, specific, incorrect heart rates — so the
algorithm is settled here, against signals whose true rate is known, before
any of it is written in Swift.

## Files

| file | purpose |
|---|---|
| `ppg_reference.py` | the pipeline: resample → detrend → bandpass → autocorrelation + FFT → confidence → RMSSD |
| `synthetic.py` | fingertip-PPG generator modelling perfusion, harmonics, breathing wander, quantisation, frame jitter |
| `validate.py` | accuracy sweep across 16 heart rates × 8 seeds × 11 scenarios |
| `calibrate_confidence.py` | derives the confidence threshold that gates a reading as reportable |
| `emit_vectors.py` | writes `Tests/PulseLogSignalTests/Resources/ppg_vectors.json` |

## Running

```bash
python3 -m venv venv && source venv/bin/activate && pip install numpy
cd reference
python validate.py             # accuracy sweep
python calibrate_confidence.py # threshold calibration
python emit_vectors.py         # regenerate Swift test vectors
```

## Results

Accuracy over 30 s windows at 30 fps, 128 runs per scenario:

| scenario | MAE | p95 | max | ≤3 BPM |
|---|---|---|---|---|
| nominal | 0.55 | 1.70 | 3.37 | 99.2% |
| weak perfusion (0.25% AC/DC) | 0.60 | 1.94 | 3.65 | 97.7% |
| heavy breathing wander (8×) | 0.55 | 1.64 | 3.41 | 99.2% |
| high sensor noise (5× nominal) | 0.68 | 2.37 | 4.26 | 97.7% |
| frame jitter + 8% drops | 0.56 | 1.71 | 3.79 | 99.2% |
| 24 fps | 0.62 | 2.27 | 4.12 | 98.4% |
| 15 s window | 0.91 | 2.53 | 4.33 | 96.9% |
| very weak perfusion (0.1%) | 2.49 | 3.32 | 100.38 | 91.4% |
| combined adverse | 20.41 | 99.60 | 149.70 | 69.5% |

The last two scenarios are why the confidence gate exists. Pooling all 864
runs and filtering by confidence:

| threshold | accepted | MAE | worst | errors >10 BPM |
|---|---|---|---|---|
| 0.30 | 88.7% | 2.49 | 110.82 | 24 |
| **0.40** | 84.3% | 0.74 | 6.14 | **0** |
| 0.45 (shipped) | 83.2% | 0.73 | 5.36 | **0** |

Above the shipped threshold no accepted reading is off by more than about 5
BPM. Below it the app asks for a retake instead of showing a number.

## Two findings worth keeping

**Octave errors are the dominant failure mode.** The dicrotic notch puts so
much energy in the second harmonic that the autocorrelation peak at 2T can
exceed the one at T — measured at 200 BPM, acf(2T)=0.628 against acf(T)=0.598.
Taking the global maximum reports exactly half the true rate.

**The obvious fix is wrong.** Arbitrating such disputes by "whichever
frequency carries more spectral power" fails in the other direction, because
for real PPG the second harmonic is often stronger than the fundamental; that
rule reported double rate for every bradycardic case in the sweep. The sound
rule is that a harmonic cannot exist without its fundamental: prefer the lower
frequency, and reject it only when it carries almost no energy. The separation
is wide enough to be safe — genuine fundamentals held P(low)/P(high) ≥ 0.442,
spurious sub-harmonics ≤ 0.012, against a threshold of 0.10.
