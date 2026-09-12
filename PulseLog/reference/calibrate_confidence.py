"""Calibrate the confidence threshold that gates a reading as reportable.

The product promise is that a displayed number is trustworthy. That requires
the confidence score to actually separate accurate estimates from inaccurate
ones, and a threshold chosen from evidence rather than taste.

Pools every scenario (favourable and adverse) and reports, for each candidate
threshold, the accuracy of the readings that would be ACCEPTED and the share
of attempts that would be rejected as a retake.
"""

import numpy as np
import ppg_reference as ppg
import synthetic

BPM_SWEEP = [45, 52, 58, 65, 72, 80, 88, 95, 105, 115, 125, 140, 155, 170, 185, 200]

SCENARIOS = [
    ("nominal", {}),
    ("weak", {"ac_dc_ratio": 0.0025}),
    ("very_weak", {"ac_dc_ratio": 0.001}),
    ("breathing", {"breathing_amplitude_ratio": 8.0}),
    ("noisy", {"sensor_noise_dc_ratio": 0.0025}),
    ("jitter", {"timestamp_jitter_s": 0.010, "drop_probability": 0.08}),
    ("short", {"duration_s": 15.0}),
    ("adverse", {"ac_dc_ratio": 0.002, "breathing_amplitude_ratio": 6.0,
                 "sensor_noise_dc_ratio": 0.0015, "timestamp_jitter_s": 0.008,
                 "drop_probability": 0.05}),
    ("garbage", {"ac_dc_ratio": 0.00005, "sensor_noise_dc_ratio": 0.004}),
]


def collect():
    rows = []
    for name, kw in SCENARIOS:
        for bpm in BPM_SWEEP:
            for seed in range(6):
                ts, sig = synthetic.generate(bpm=bpm, seed=seed, **kw)
                r = ppg.analyze(ts, sig)
                if r["bpm"] is None:
                    rows.append((name, bpm, None, 0.0))
                else:
                    rows.append((name, bpm, r["bpm"], r["confidence"]))
    return rows


def main():
    rows = collect()
    total = len(rows)
    conf = np.array([r[3] for r in rows])
    err = np.array([abs(r[2] - r[1]) if r[2] is not None else 999.0 for r in rows])

    print("=" * 92)
    print(f"Confidence calibration over {total} runs across {len(SCENARIOS)} scenarios")
    print("=" * 92)
    print(f"{'thresh':>7}{'accepted':>10}{'accept%':>9}{'MAE':>8}{'p95':>8}{'max':>9}"
          f"{'<=3bpm%':>9}{'>10bpm':>8}")
    print("-" * 92)

    best = None
    for t in [0.0, 0.20, 0.30, 0.40, 0.45, 0.50, 0.55, 0.60, 0.65, 0.70, 0.75]:
        sel = conf >= t
        n = int(sel.sum())
        if n == 0:
            print(f"{t:7.2f}{0:10d}     -- all rejected --")
            continue
        e = err[sel]
        mae, p95, mx = e.mean(), np.percentile(e, 95), e.max()
        w3 = (e <= 3.0).mean() * 100
        bad = int((e > 10.0).sum())
        print(f"{t:7.2f}{n:10d}{n/total*100:8.1f}%{mae:8.2f}{p95:8.2f}{mx:9.2f}{w3:8.1f}%{bad:8d}")
        # Production criterion: no accepted reading off by more than 10 BPM,
        # while still accepting a usable majority of attempts.
        if bad == 0 and best is None and n / total >= 0.50:
            best = (t, n / total * 100, mae, mx)

    print("-" * 92)
    if best:
        print(f"\nRECOMMENDED THRESHOLD: {best[0]:.2f}")
        print(f"  accepts {best[1]:.1f}% of attempts | MAE {best[2]:.2f} BPM | worst {best[3]:.2f} BPM")
        print("  zero accepted readings off by more than 10 BPM")
    else:
        print("\nNo threshold satisfies the criterion; estimator needs more work.")
    return 0 if best else 1


if __name__ == "__main__":
    raise SystemExit(main())
