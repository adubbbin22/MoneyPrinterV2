import Foundation

/// Short facts shown during the 30-second capture.
///
/// Holding still for half a minute while a progress ring creeps round feels
/// broken; something to read turns dead time into a reason to stay put. The
/// incumbent apps worked this out, and it is the best idea in them.
///
/// These are health claims displayed in a health app, so each is a settled
/// piece of physiology rather than a striking-sounding number. Anything the
/// author could not state with confidence was left out, and several popular
/// ones are here specifically to correct a common myth.
enum CardiovascularFacts {

    static let all: [String] = [
        // Scale
        "Your heart beats roughly 100,000 times a day — around 2.5 billion times in an average lifetime.",
        "At rest your heart pumps about 5 litres of blood every minute. That is your entire blood volume, once a minute.",
        "A single drop of blood completes a full circuit of your body in about a minute.",
        "The heart is roughly the size of your closed fist, and sits slightly left of centre behind the breastbone.",
        "A resting heart moves around 7,000 litres of blood a day.",

        // Anatomy
        "The left ventricle has a much thicker wall than the right: it pushes blood around the whole body, while the right only reaches the lungs.",
        "Pressure in the arteries to your lungs is far lower than in the rest of your body — roughly 25/10 rather than 120/80.",
        "Your coronary arteries fill between beats, not during them. The heart feeds itself while it relaxes.",
        "The aorta, the largest artery, is about the width of a garden hose where it leaves the heart.",
        "Capillaries are so narrow that red blood cells have to fold to pass through them single file.",

        // Rhythm
        "Your heart has its own pacemaker. The sinoatrial node fires on its own, which is why a heart can keep beating outside the body if kept oxygenated.",
        "The gap between your beats is never exactly the same twice. That variation is a sign of a responsive nervous system, not a fault.",
        "The lub-dub of a heartbeat is the sound of valves closing, not of the muscle squeezing.",
        "Your vagus nerve acts as a brake on your heart. Slow breathing increases its influence, which is why it lowers heart rate.",
        "Putting your face in cold water slows your heart within seconds — a reflex shared with diving mammals.",
        "Heart rate falls during deep sleep, often well below your usual daytime resting rate.",

        // Blood
        "Blood is red whether or not it is carrying oxygen. Deoxygenated blood is dark red, never blue.",
        "Veins look blue through skin because of how light scatters in tissue, not because the blood inside them is blue.",
        "A single red blood cell lives about four months, then is broken down and its iron recycled.",
        "One haemoglobin molecule carries up to four oxygen molecules at a time.",
        "Most of your blood is in your veins at any given moment; they act as a reservoir rather than just a return route.",

        // Measurement
        "This measurement works because blood absorbs light. Each beat pushes more blood into your fingertip, and slightly less light reaches the camera.",
        "Fingertips are used for pulse measurement because they are unusually dense with small blood vessels.",
        "Hospital pulse oximeters use the same principle as this measurement, with two wavelengths of light instead of one.",
        "Blood pressure is measured in millimetres of mercury because the first reliable gauges used a column of mercury.",
        "Systolic is the pressure as your heart contracts; diastolic is the pressure while it refills.",

        // Practical
        "A blood pressure cuff that is too small for your arm reads high. Cuff size is one of the most common sources of error at home.",
        "Resting your arm below heart level can add several mmHg to a blood pressure reading. Support it at chest height.",
        "Talking during a blood pressure measurement can raise the result by around 10 mmHg.",
        "A full bladder can raise blood pressure noticeably. It is worth taking care of first.",
        "The first reading of a session is often the highest. This is why guidance suggests taking two or three and averaging.",
        "Blood pressure normally dips overnight. Someone whose pressure stays flat at night is described as a non-dipper.",
        "White coat hypertension is real: blood pressure genuinely rises in clinical settings for many people, which is why home readings are useful.",
        "Caffeine can raise blood pressure for a few hours, so it is worth noting on any reading taken soon after coffee.",

        // Fitness
        "Trained endurance athletes often have resting heart rates in the 40s. Some competitive cyclists have been recorded below 30.",
        "Regular aerobic exercise lowers resting heart rate by strengthening the heart, so it moves more blood per beat.",
        "Stroke volume — blood ejected per beat — is around 70 millilitres at rest in a typical adult.",
        "Standing up briefly raises your heart rate as your body compensates for blood pooling in your legs.",
        "Heart rate recovery — how fast your pulse falls after exercise — is one of the more informative things you can observe about fitness.",
        "Dehydration raises resting heart rate, because less blood volume means more beats to deliver the same oxygen.",
    ]

    /// A shuffled run through every fact before any repeats.
    ///
    /// Random selection would show the same card twice in one 30-second
    /// capture often enough to feel broken.
    static func sequence(seed: UInt64 = UInt64.random(in: 0...UInt64.max)) -> [String] {
        var generator = SplitMix64(seed: seed)
        return all.shuffled(using: &generator)
    }
}

/// Small deterministic generator so the fact order can be reproduced in tests.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
