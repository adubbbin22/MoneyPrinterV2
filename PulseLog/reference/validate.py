"""Validation sweep for the PPG pipeline. Prints error statistics per scenario."""

import sys
import numpy as np
import ppg_reference as ppg
import synthetic

BPM_SWEEP = [45, 52, 58, 65, 72, 80, 88, 95, 105, 115, 125, 140, 155, 170, 185, 200]
SEEDS = range(8)


def run_scenario(name, **kwargs):
    errors, confidences, failures = [], [], 0
    for bpm in BPM_SWEEP:
        for seed in SEEDS:
            ts, sig = synthetic.generate(bpm=bpm, seed=seed, **kwargs)
            res = ppg.analyze(ts, sig)
            if res["bpm"] is None:
                failures += 1
                continue
            errors.append(abs(res["bpm"] - bpm))
            confidences.append(res["confidence"])

    errors = np.asarray(errors)
    confidences = np.asarray(confidences)
    n = errors.size
    if n == 0:
        print(f"{name:<34} NO ESTIMATES ({failures} failures)")
        return None

    mae = errors.mean()
    p95 = np.percentile(errors, 95)
    worst = errors.max()
    within3 = (errors <= 3.0).mean() * 100
    print(
        f"{name:<34} MAE={mae:6.2f}  p95={p95:6.2f}  max={worst:6.2f}  "
        f"<=3bpm={within3:5.1f}%  conf={confidences.mean():.2f}  n={n}  fail={failures}"
    )
    return {"mae": mae, "p95": p95, "max": worst, "within3": within3,
            "conf": confidences.mean(), "n": n, "failures": failures}


def main():
    print("=" * 108)
    print("PPG pipeline validation - 30s windows @ 30fps, 8 seeds x 16 heart rates per scenario")
    print("=" * 108)

    results = {}
    results["nominal"] = run_scenario("Nominal (typical finger contact)")
    results["weak"] = run_scenario("Weak perfusion (AC/DC 0.25%)", ac_dc_ratio=0.0025)
    results["very_weak"] = run_scenario("Very weak perfusion (0.1%)", ac_dc_ratio=0.001)
    results["breathing"] = run_scenario("Heavy breathing wander (8x)", breathing_amplitude_ratio=8.0)
    results["noisy"] = run_scenario("High sensor noise (5x nominal)", sensor_noise_dc_ratio=0.0025)
    results["small_roi"] = run_scenario("Small ROI (2500 px)", roi_pixels=2500)
    results["jitter"] = run_scenario("Heavy frame jitter + 8% drops",
                                     timestamp_jitter_s=0.010, drop_probability=0.08)
    results["low_fps"] = run_scenario("Low frame rate (24 fps)", fps=24.0)
    results["short"] = run_scenario("Short window (15s)", duration_s=15.0)
    results["high_hrv"] = run_scenario("High HRV (60ms SD)", hrv_sd_ms=60.0)
    results["worst"] = run_scenario("Combined adverse",
                                    ac_dc_ratio=0.002, breathing_amplitude_ratio=6.0,
                                    sensor_noise_dc_ratio=0.0015, timestamp_jitter_s=0.008,
                                    drop_probability=0.05)

    print("=" * 108)

    # Gate: the nominal case is what the product ships against.
    nominal = results["nominal"]
    ok = nominal is not None and nominal["mae"] < 3.0 and nominal["within3"] > 90.0
    print(f"\nGATE (nominal MAE < 3.0 BPM and >90% within 3 BPM): {'PASS' if ok else 'FAIL'}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
