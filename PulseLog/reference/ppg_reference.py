"""
PulseLog PPG reference implementation.

This is the numerically-validated reference for the heart-rate estimation
pipeline. The Swift implementation in PulseLog/Sources/PulseLogSignal is a
direct port of this file, and its unit tests assert against test vectors
generated here (see emit_vectors.py).

Pipeline:
    raw red-channel means + timestamps
      -> uniform resample (camera timestamps jitter)
      -> DC removal via 1s moving-average detrend
      -> Butterworth bandpass 0.7-3.5 Hz (42-210 BPM), zero-phase
      -> autocorrelation period estimate w/ octave-error guard + parabolic refine
      -> FFT cross-check
      -> confidence score
      -> peak detection -> RR intervals -> RMSSD

Deliberately dependency-light: numpy only, no scipy, so every operation has a
straightforward Swift equivalent.
"""

import math
import numpy as np

# Physiological search band. 42-210 BPM covers bradycardia through peak exertion.
MIN_BPM = 42.0
MAX_BPM = 210.0
LOW_HZ = MIN_BPM / 60.0   # 0.70 Hz
HIGH_HZ = MAX_BPM / 60.0  # 3.50 Hz

# In an octave dispute, the lower frequency is accepted as the fundamental
# unless its band power falls below this fraction of the higher frequency's.
# Empirically calibrated: see the comment in analyze().
SUBHARMONIC_POWER_FLOOR = 0.10

# RR-interval coefficient of variation above which confidence is reduced.
# A steady pulse sits well below this; sustained values above it mean the
# single-dominant-period model does not fit the data it is being applied to.
RR_DISPERSION_TOLERANCE = 0.12

# Samples per beat below which sub-sample refinement is doing the heavy
# lifting and interval scatter starts to bias the estimate. At 30 fps this is
# roughly 128 BPM and above.
SPARSE_PERIOD_SAMPLES = 14.0

# Minimum confidence for a reading to be shown to the user. Calibrated over 864
# runs spanning nine scenarios (see calibrate_confidence.py): at 0.40 the count
# of accepted readings in error by more than 10 BPM drops from 24 to zero, and
# 0.45 keeps a safety margin while still accepting 83% of attempts.
# Below this, ask for a retake rather than display a number.
CONFIDENCE_THRESHOLD = 0.45


# --------------------------------------------------------------------------
# Resampling
# --------------------------------------------------------------------------

def resample_uniform(timestamps, values):
    """Linearly resample onto a uniform grid at the median observed rate.

    Camera frame delivery is not isochronous: AVCaptureSession drops and
    delays frames under thermal or exposure pressure. Treating jittered
    samples as uniform smears the spectrum and biases the estimate, so this
    step is not optional.
    """
    ts = np.asarray(timestamps, dtype=np.float64)
    vs = np.asarray(values, dtype=np.float64)
    if ts.size < 2:
        return 0.0, vs

    dt = np.diff(ts)
    median_dt = float(np.median(dt))
    if median_dt <= 0:
        return 0.0, vs

    fs = 1.0 / median_dt
    n = int(math.floor((ts[-1] - ts[0]) / median_dt)) + 1
    grid = ts[0] + np.arange(n) * median_dt
    return fs, np.interp(grid, ts, vs)


# --------------------------------------------------------------------------
# Detrend + filtering
# --------------------------------------------------------------------------

def moving_average_detrend(x, fs, window_seconds=1.0):
    """Subtract a centred moving average to kill DC and slow wander.

    The torch pushes the red channel near saturation, so the DC term dwarfs
    the pulsatile component (AC/DC is typically well under 1%). Removing it
    first keeps the later stages numerically well-conditioned.
    """
    x = np.asarray(x, dtype=np.float64)
    w = max(3, int(round(window_seconds * fs)))
    if w % 2 == 0:
        w += 1
    if w >= x.size:
        return x - x.mean()

    half = w // 2
    padded = np.pad(x, (half, half), mode="edge")
    kernel = np.ones(w, dtype=np.float64) / w
    baseline = np.convolve(padded, kernel, mode="valid")
    return x - baseline


def _butter2_lowpass_coeffs(cutoff_hz, fs):
    """2nd-order Butterworth lowpass biquad via bilinear transform."""
    nyq = fs * 0.5
    fc = min(max(cutoff_hz, 1e-6), nyq * 0.999)
    w0 = math.tan(math.pi * fc / fs)
    k = math.sqrt(2.0)
    denom = 1.0 + k * w0 + w0 * w0
    b0 = w0 * w0 / denom
    b1 = 2.0 * b0
    b2 = b0
    a1 = 2.0 * (w0 * w0 - 1.0) / denom
    a2 = (1.0 - k * w0 + w0 * w0) / denom
    return (b0, b1, b2, a1, a2)


def _butter2_highpass_coeffs(cutoff_hz, fs):
    """2nd-order Butterworth highpass biquad via bilinear transform."""
    nyq = fs * 0.5
    fc = min(max(cutoff_hz, 1e-6), nyq * 0.999)
    w0 = math.tan(math.pi * fc / fs)
    k = math.sqrt(2.0)
    denom = 1.0 + k * w0 + w0 * w0
    b0 = 1.0 / denom
    b1 = -2.0 * b0
    b2 = b0
    a1 = 2.0 * (w0 * w0 - 1.0) / denom
    a2 = (1.0 - k * w0 + w0 * w0) / denom
    return (b0, b1, b2, a1, a2)


def biquad_forward(x, coeffs):
    b0, b1, b2, a1, a2 = coeffs
    y = np.empty_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(x.size):
        xi = x[i]
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        y[i] = yi
        x2, x1 = x1, xi
        y2, y1 = y1, yi
    return y


def filtfilt_biquad(x, coeffs):
    """Zero-phase filtering: forward, reverse, forward, reverse.

    Phase distortion would shift detected peak positions and corrupt the RR
    intervals that RMSSD depends on, so the filter must be zero-phase.
    """
    y = biquad_forward(np.asarray(x, dtype=np.float64), coeffs)
    y = biquad_forward(y[::-1].copy(), coeffs)[::-1].copy()
    return y


def bandpass(x, fs, low_hz=LOW_HZ, high_hz=HIGH_HZ):
    y = filtfilt_biquad(x, _butter2_highpass_coeffs(low_hz, fs))
    y = filtfilt_biquad(y, _butter2_lowpass_coeffs(high_hz, fs))
    return y


# --------------------------------------------------------------------------
# Period estimation
# --------------------------------------------------------------------------

def autocorrelation(x):
    """Unbiased-ish normalised autocorrelation via FFT (Wiener-Khinchin)."""
    x = np.asarray(x, dtype=np.float64)
    x = x - x.mean()
    n = x.size
    if n == 0 or np.allclose(x, 0.0):
        return np.zeros(n)
    nfft = 1 << (2 * n - 1).bit_length()
    spec = np.fft.rfft(x, nfft)
    acf = np.fft.irfft(spec * np.conjugate(spec), nfft)[:n]
    if acf[0] <= 0:
        return np.zeros(n)
    return acf / acf[0]


def _parabolic_refine(values, index):
    """Sub-sample peak location by fitting a parabola to 3 points.

    At 30 fps and 180 BPM the period is only 10 samples, so a whole-sample
    quantisation is worth ~18 BPM. Interpolation is what makes a 30 fps
    camera viable at high heart rates at all.
    """
    if index <= 0 or index >= values.size - 1:
        return float(index)
    a, b, c = values[index - 1], values[index], values[index + 1]
    denom = a - 2.0 * b + c
    if abs(denom) < 1e-12:
        return float(index)
    delta = 0.5 * (a - c) / denom
    if not (-1.0 < delta < 1.0):
        return float(index)
    return float(index) + delta


def band_power(filtered, fs, bpm, rel_width=0.08):
    """Periodogram power in a narrow band around `bpm`.

    Used to arbitrate octave disputes between the two estimators: the true
    fundamental carries more energy than a spurious sub-harmonic, which has
    no independent existence in the spectrum at all.
    """
    x = np.asarray(filtered, dtype=np.float64)
    n = x.size
    if n < 8 or bpm is None or bpm <= 0:
        return 0.0
    window = np.hanning(n)
    nfft = 1 << (4 * n - 1).bit_length()
    spec = np.abs(np.fft.rfft(x * window, nfft)) ** 2
    freqs = np.fft.rfftfreq(nfft, d=1.0 / fs)
    f0 = bpm / 60.0
    sel = (freqs >= f0 * (1.0 - rel_width)) & (freqs <= f0 * (1.0 + rel_width))
    if not sel.any():
        return 0.0
    return float(spec[sel].sum())


def estimate_bpm_autocorr(filtered, fs, subharmonic_tolerance=0.70):
    """Dominant period from autocorrelation, guarding against octave errors.

    A periodic signal produces autocorrelation peaks at T, 2T, 3T ... and the
    dicrotic notch puts enough energy in the second harmonic that the 2T peak
    can be TALLER than the true T peak -- measured at 200 BPM, acf(2T)=0.628
    vs acf(T)=0.598. Taking the global maximum therefore reports half rate.

    So: locate the global best lag, then explicitly probe its integer
    sub-multiples (T_best/2, /3, /4). If a genuine local maximum sits near one
    of them with correlation within `subharmonic_tolerance` of the best, that
    shorter lag is the real fundamental and wins.
    """
    acf = autocorrelation(filtered)
    if acf.size == 0:
        return None, 0.0

    min_lag = max(2, int(math.floor(fs * 60.0 / MAX_BPM)))
    max_lag = min(acf.size - 2, int(math.ceil(fs * 60.0 / MIN_BPM)))
    if max_lag <= min_lag:
        return None, 0.0

    candidates = [
        lag for lag in range(min_lag, max_lag + 1)
        if acf[lag] > acf[lag - 1] and acf[lag] >= acf[lag + 1] and acf[lag] > 0
    ]
    if not candidates:
        return None, 0.0

    best_lag = max(candidates, key=lambda l: acf[l])
    best_value = acf[best_lag]
    if best_value <= 0:
        return None, 0.0

    # Probe integer sub-multiples of the winning lag for the true fundamental.
    chosen = best_lag
    for divisor in (4, 3, 2):
        target = best_lag / divisor
        if target < min_lag:
            continue
        near = [l for l in candidates if abs(l - target) <= 1.5]
        if not near:
            continue
        contender = max(near, key=lambda l: acf[l])
        if acf[contender] >= best_value * subharmonic_tolerance:
            chosen = contender
            break

    refined = _parabolic_refine(acf, chosen)
    if refined <= 0:
        return None, 0.0

    bpm = 60.0 * fs / refined
    if not (MIN_BPM <= bpm <= MAX_BPM):
        return None, 0.0
    return bpm, float(acf[chosen])


def estimate_bpm_fft(filtered, fs):
    """Dominant frequency via zero-padded periodogram. Used as a cross-check."""
    x = np.asarray(filtered, dtype=np.float64)
    n = x.size
    if n < 8:
        return None, 0.0
    # Hann window suppresses spectral leakage from the finite record.
    window = np.hanning(n)
    nfft = 1 << (4 * n - 1).bit_length()
    spec = np.abs(np.fft.rfft(x * window, nfft))
    freqs = np.fft.rfftfreq(nfft, d=1.0 / fs)

    band = (freqs >= LOW_HZ) & (freqs <= HIGH_HZ)
    if not band.any():
        return None, 0.0
    band_spec = np.where(band, spec, 0.0)
    peak = int(np.argmax(band_spec))
    if band_spec[peak] <= 0:
        return None, 0.0

    refined = _parabolic_refine(band_spec, peak)
    df = freqs[1] - freqs[0]
    freq = refined * df
    total = band_spec.sum()
    purity = float(band_spec[peak] / total) if total > 0 else 0.0
    bpm = freq * 60.0
    if not (MIN_BPM <= bpm <= MAX_BPM):
        return None, 0.0
    return bpm, purity


# --------------------------------------------------------------------------
# Peak detection / HRV
# --------------------------------------------------------------------------

def detect_peaks(filtered, fs, expected_bpm):
    """Peak picking with a refractory period derived from the estimated rate.

    Refractory = 60% of the expected beat interval; physiologically no second
    systolic peak can occur that soon, so this rejects dicrotic notches being
    counted as beats.
    """
    x = np.asarray(filtered, dtype=np.float64)
    if x.size < 3 or expected_bpm is None or expected_bpm <= 0:
        return []

    refractory = max(1, int(round(0.6 * fs * 60.0 / expected_bpm)))
    threshold = 0.3 * np.std(x)

    peaks = []
    last = -(10 ** 9)
    for i in range(1, x.size - 1):
        if x[i] > x[i - 1] and x[i] >= x[i + 1] and x[i] > threshold:
            if i - last >= refractory:
                peaks.append(i)
                last = i
            elif peaks and x[i] > x[peaks[-1]]:
                # A taller peak inside the refractory window replaces the last.
                peaks[-1] = i
                last = i
    return peaks


def rr_dispersion(peaks, fs):
    """Coefficient of variation of the RR intervals.

    Measures how well the "one dominant period" assumption actually fits. A
    steady pulse gives a few percent; a poorly-tracked or genuinely erratic one
    gives far more. This is the evidence that the estimate rests on a shaky
    premise, independent of how tall the autocorrelation peak is.
    """
    if len(peaks) < 4:
        return None
    rr = np.diff(np.asarray(peaks, dtype=np.float64)) / fs * 1000.0
    rr = rr[(rr >= 250.0) & (rr <= 2000.0)]
    if rr.size < 3:
        return None
    mean = rr.mean()
    if mean <= 0:
        return None
    return float(rr.std(ddof=1) / mean)


def rmssd_ms(peaks, fs):
    """Root mean square of successive RR-interval differences, in ms."""
    if len(peaks) < 3:
        return None
    rr = np.diff(np.asarray(peaks, dtype=np.float64)) / fs * 1000.0
    # Drop physiologically implausible intervals (missed/extra detections).
    rr = rr[(rr >= 250.0) & (rr <= 2000.0)]
    if rr.size < 2:
        return None
    diffs = np.diff(rr)
    return float(np.sqrt(np.mean(diffs ** 2)))


# --------------------------------------------------------------------------
# Top level
# --------------------------------------------------------------------------

def analyze(timestamps, values):
    """Full pipeline. Returns a dict with bpm, confidence, hrv and diagnostics."""
    fs, uniform = resample_uniform(timestamps, values)
    if fs <= 0 or uniform.size < 16:
        return {"bpm": None, "confidence": 0.0, "rmssd_ms": None, "fs": fs}

    detrended = moving_average_detrend(uniform, fs, window_seconds=1.0)
    filtered = bandpass(detrended, fs)

    ac_bpm, ac_strength = estimate_bpm_autocorr(filtered, fs)
    fft_bpm, fft_purity = estimate_bpm_fft(filtered, fs)

    # Autocorrelation is the primary estimator: it degrades more gracefully on
    # short records than a periodogram, whose resolution is bounded by 1/T.
    bpm = ac_bpm if ac_bpm is not None else fft_bpm
    if bpm is None:
        return {"bpm": None, "confidence": 0.0, "rmssd_ms": None, "fs": fs}

    # Octave arbitration. If the two estimators sit in a ~2:1 (or 3:1)
    # relationship, one has locked onto a harmonic or a sub-harmonic.
    #
    # The naive rule "more band power wins" is WRONG for PPG: the dicrotic
    # notch routinely makes the second harmonic stronger than the fundamental,
    # so that rule reports double rate for every bradycardic subject.
    #
    # The sound principle is that a harmonic can only exist if its fundamental
    # does. So prefer the LOWER frequency, and only reject it when it carries
    # essentially no energy -- which is the signature of autocorrelation having
    # locked onto 2T rather than T.
    #
    # Measured separation on the validation corpus:
    #   genuine fundamental   P(low)/P(high) >= 0.442
    #   spurious sub-harmonic P(low)/P(high) <= 0.012
    # The threshold below sits between them with ~10x margin on either side.
    octave_resolved = False
    if ac_bpm is not None and fft_bpm is not None:
        ratio = max(ac_bpm, fft_bpm) / min(ac_bpm, fft_bpm)
        if abs(ratio - 2.0) < 0.25 or abs(ratio - 3.0) < 0.30:
            lower, higher = min(ac_bpm, fft_bpm), max(ac_bpm, fft_bpm)
            p_low = band_power(filtered, fs, lower)
            p_high = band_power(filtered, fs, higher)
            bpm = lower if (p_high <= 0 or p_low / p_high >= SUBHARMONIC_POWER_FLOOR) else higher
            octave_resolved = True

    # Agreement between two independent estimators is the strongest available
    # evidence that the periodicity is real rather than an artifact.
    if ac_bpm is not None and fft_bpm is not None:
        disagreement = abs(ac_bpm - fft_bpm) / max(ac_bpm, fft_bpm)
        agreement = max(0.0, 1.0 - disagreement / 0.10)
        if octave_resolved:
            # The estimators disagreed and we picked a winner on spectral
            # evidence. That is weaker grounds than native agreement, so the
            # reading is capped rather than credited.
            agreement = min(agreement, 0.40)
    else:
        agreement = 0.0

    peaks = detect_peaks(filtered, fs, bpm)
    hrv = rmssd_ms(peaks, fs)

    confidence = float(np.clip(
        0.55 * max(0.0, ac_strength) + 0.25 * agreement + 0.20 * min(1.0, fft_purity * 8.0),
        0.0, 1.0,
    ))

    # Penalise estimates whose own beat intervals contradict the single-period
    # model they rest on. Measured failure mode: at 185-210 BPM with large
    # beat-to-beat variability the period is short enough (300 ms at 200 BPM)
    # that the variability is a fifth of it, the autocorrelation peak smears,
    # and refinement drifts toward longer lags -- producing estimates biased
    # low by 10-14 BPM that the other confidence terms rate as fine.
    #
    # A steady pulse holds RR dispersion to a few percent, so a penalty above
    # RR_DISPERSION_TOLERANCE targets exactly those cases.
    # The penalty applies only where the mechanism does. Fragility comes from
    # having few samples per beat: at 30 fps and 200 BPM a period spans just 9
    # samples, so sub-sample refinement carries the estimate and interval
    # scatter throws it off. At 60 BPM the same dispersion spreads over 30
    # samples and is simply ordinary heart-rate variability, which must not be
    # punished -- doing so rejected half of all weak-perfusion readings for no
    # accuracy gain.
    dispersion = rr_dispersion(peaks, fs)
    samples_per_period = fs * 60.0 / bpm
    if (dispersion is not None
            and dispersion > RR_DISPERSION_TOLERANCE
            and samples_per_period < SPARSE_PERIOD_SAMPLES):
        excess = (dispersion - RR_DISPERSION_TOLERANCE) / RR_DISPERSION_TOLERANCE
        sparsity = (SPARSE_PERIOD_SAMPLES - samples_per_period) / SPARSE_PERIOD_SAMPLES
        confidence *= float(max(0.0, 1.0 - 0.9 * min(1.0, excess) * min(1.0, sparsity * 3.0)))

    return {
        "bpm": float(bpm),
        "confidence": confidence,
        "rmssd_ms": hrv,
        "fs": float(fs),
        "autocorr_bpm": ac_bpm,
        "fft_bpm": fft_bpm,
        "autocorr_strength": float(ac_strength),
        "beat_count": len(peaks),
        "rr_dispersion": dispersion,
        "octave_resolved": octave_resolved,
        "is_reportable": confidence >= CONFIDENCE_THRESHOLD,
    }
