//
//  OnboardingView.swift
//  StreamSnip
//
//  First-run wizard: welcome, add a source, done. Shown once, on first launch.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var model = OnboardingModel()
    @State private var showingAddSource = false
    @State private var accountBaseline = 0

    var body: some View {
        Group {
            switch model.step {
            case .welcome:
                welcomeStep
            case .allSet:
                allSetStep
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
        .sheet(isPresented: $showingAddSource, onDismiss: {
            // A source may have been added, or the user backed out to pick
            // later — only claim success when an account actually exists.
            let addedSource = (appEnvironment?.accountsManager.accounts.count ?? 0) > accountBaseline
            if !model.hasAddedSource {
                model.addSourceDismissed(addedSource: addedSource)
            }
        }) {
            if let appEnvironment {
                AddSourceView()
                    .appEnvironment(appEnvironment)
            } else {
                AddSourceView()
            }
        }
    }

    // MARK: - Steps

    private var welcomeStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "scissors.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(String(localized: "onboarding.welcome.title", defaultValue: "Welcome to StreamSnip"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            Text(String(localized: "onboarding.welcome.message", defaultValue: "Play video from your own sources — Invidious, Piped, PeerTube, Jellyfin, Yattee Server, local folders, SMB and WebDAV — and snip the moments worth keeping."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                Button {
                    accountBaseline = appEnvironment?.accountsManager.accounts.count ?? 0
                    showingAddSource = true
                } label: {
                    Label(String(localized: "onboarding.addSource", defaultValue: "Add a Source"), systemImage: "plus")
                        .frame(maxWidth: 320)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button(String(localized: "onboarding.skip", defaultValue: "Skip — I'll add one later")) {
                    model.skip()
                }
                .font(.subheadline)
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var allSetStep: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: model.hasAddedSource ? "checkmark.circle.fill" : "play.circle")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text(String(localized: "onboarding.allSet.title", defaultValue: "You're All Set"))
                .font(.largeTitle.bold())

            Text(model.hasAddedSource
                ? String(localized: "onboarding.allSet.message", defaultValue: "Your source is ready. Find more any time in Settings → Sources.")
                : String(localized: "onboarding.allSet.skipped", defaultValue: "You can add sources any time in Settings → Sources."))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            Button {
                model.finish()
            } label: {
                Text(String(localized: "common.done"))
                    .frame(maxWidth: 320)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
