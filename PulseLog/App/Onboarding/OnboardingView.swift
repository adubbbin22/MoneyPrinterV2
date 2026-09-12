import SwiftUI

/// First-run explanation.
///
/// The honesty here is the product position, not a legal formality. These apps
/// are searched for by people who want their blood pressure measured, and the
/// category's convention is to let that misunderstanding stand. Correcting it
/// on the first screen costs some installs and earns the trust that everything
/// else depends on.
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var page = 0

    var body: some View {
        TabView(selection: $page) {
            OnboardingPage(
                symbol: "heart.text.square",
                title: "Measure your heart rate",
                body: "Rest a fingertip over the rear camera and flash. Each heartbeat "
                    + "pushes blood into your finger, which changes how much light gets "
                    + "through. PulseLog reads that rhythm.",
                accent: nil
            ).tag(0)

            OnboardingPage(
                symbol: "exclamationmark.shield",
                title: "What this app does not do",
                body: "PulseLog cannot measure your blood pressure, and neither can any "
                    + "other app using only a phone camera. There is no validated method "
                    + "for it. You can log blood pressure here, but the numbers have to "
                    + "come from a real cuff.",
                accent: "This is the honest version. Apps that claim otherwise are "
                      + "guessing, and their guesses have been measured as wrong."
            ).tag(1)

            OnboardingPage(
                symbol: "chart.line.uptrend.xyaxis",
                title: "The value is in the pattern",
                body: "One reading tells you little. Dozens, tagged with what you were "
                    + "doing, start to show what moves your heart rate — sleep, caffeine, "
                    + "stress, training. PulseLog only reports a pattern once there is "
                    + "enough data to trust it.",
                accent: nil
            ).tag(2)

            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "checkmark.seal")
                    .font(.system(size: 56)).foregroundStyle(Theme.accent)
                Text("One more thing").font(.title.weight(.semibold))

                Text("PulseLog is a wellness tool, not a medical device. It does not "
                     + "diagnose, treat, or monitor any condition. If something in your "
                     + "readings worries you, talk to a doctor rather than to an app.")
                    .font(.callout).multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()
                Button {
                    hasCompletedOnboarding = true
                } label: {
                    Text("Get started").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Theme.accent)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
            }
            .tag(3)
        }
        .tabViewStyle(.page)
        .background(Theme.pageBackground)
    }
}

struct OnboardingPage: View {
    let symbol: String
    let title: String
    let body: String
    let accent: String?

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 56)).foregroundStyle(Theme.accent)
            Text(title).font(.title.weight(.semibold)).multilineTextAlignment(.center)
            Text(body)
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 28)
            if let accent {
                Text(accent)
                    .font(.footnote)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Theme.accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 28)
            }
            Spacer(); Spacer()
        }
    }
}
