"""Synthetic fingertip-PPG generator used to validate the estimation pipeline.

Models the signal characteristics that actually matter for a phone camera:

  * A tiny pulsatile component. Fingertip AC/DC ratio is typically 0.2-2%;
    the torch drives the red channel near saturation, so the pulse rides on a
    very large DC pedestal.
  * Harmonic content. The dicrotic notch makes the second harmonic strong,
    which is precisely what causes naive autocorrelation to report half rate.
  * Respiratory baseline wander at 0.2-0.35 Hz with an amplitude several times
    the pulse amplitude. This dominates the raw trace.
  * 8-bit quantisation, reduced by averaging over an ROI of N pixels.
  * Sensor noise referenced to the DC level, so that reducing perfusion
    genuinely degrades SNR rather than leaving it invariant.
  * Frame timestamp jitter and occasional dropped frames.
"""

import numpy as np


def generate(
    bpm,
    duration_s=30.0,
    fps=30.0,
    ac_dc_ratio=0.008,
    dc_level=0.85,
    breathing_amplitude_ratio=3.0,
    breathing_hz=0.25,
    sensor_noise_dc_ratio=0.0005,
    roi_pixels=10000,
    timestamp_jitter_s=0.003,
    drop_probability=0.01,
    hrv_sd_ms=25.0,
    seed=0,
):
    rng = np.random.default_rng(seed)
    n = int(duration_s * fps)

    # --- frame timing: jitter + dropped frames -------------------------------
    ideal = np.arange(n) / fps
    jitter = rng.normal(0.0, timestamp_jitter_s, n)
    ts = np.sort(ideal + jitter)
    keep = rng.random(n) >= drop_probability
    keep[0] = keep[-1] = True
    ts = ts[keep]

    # --- beat phase with heart-rate variability ------------------------------
    # Integrate an instantaneous rate that wanders, so successive RR intervals
    # differ the way a real heart's do.
    mean_period = 60.0 / bpm
    hrv_sd_s = hrv_sd_ms / 1000.0
    n_beats = int(np.ceil(duration_s / mean_period)) + 4
    intervals = rng.normal(mean_period, hrv_sd_s, n_beats)
    intervals = np.clip(intervals, mean_period * 0.6, mean_period * 1.4)
    beat_times = np.concatenate([[0.0], np.cumsum(intervals)])
    # Phase in cycles at each sample, by inverting the beat-time mapping.
    phase = np.interp(ts, beat_times, np.arange(beat_times.size))

    # --- pulsatile waveform: fundamental + harmonics -------------------------
    ac = ac_dc_ratio * dc_level
    pulse = (
        1.00 * np.sin(2 * np.pi * phase)
        + 0.55 * np.sin(4 * np.pi * phase + 1.1)   # dicrotic notch energy
        + 0.22 * np.sin(6 * np.pi * phase + 2.3)
    )
    pulse = pulse / np.max(np.abs(pulse)) * ac

    # --- respiratory baseline wander -----------------------------------------
    wander = (
        breathing_amplitude_ratio * ac
        * np.sin(2 * np.pi * breathing_hz * ts + rng.uniform(0, 2 * np.pi))
    )
    # Slow thermal/pressure drift over the whole record.
    drift = 2.0 * ac * (ts / max(ts[-1], 1e-9)) * rng.uniform(-1.0, 1.0)

    signal = dc_level + pulse + wander + drift

    # --- sensor noise ---------------------------------------------------------
    # Absolute, as a fraction of the DC pedestal -- NOT of the pulse amplitude.
    # Camera read/shot noise does not shrink when perfusion is poor, which is
    # exactly why cold fingers are the dominant real-world failure mode.
    signal = signal + rng.normal(0.0, sensor_noise_dc_ratio * dc_level, signal.size)

    # --- 8-bit quantisation, averaged over the ROI ---------------------------
    # Averaging M independent quantised pixels reduces quantisation error by
    # sqrt(M); this is why the ROI must be large.
    q_step = 1.0 / 255.0
    q_noise_sd = q_step / np.sqrt(12.0 * max(roi_pixels, 1))
    signal = signal + rng.normal(0.0, q_noise_sd, signal.size)
    signal = np.clip(signal, 0.0, 1.0)

    return ts, signal
