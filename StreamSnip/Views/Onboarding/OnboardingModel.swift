//
//  OnboardingModel.swift
//  StreamSnip
//
//  First-run onboarding flow state.
//

import Foundation

/// The steps of the first-run onboarding wizard.
enum OnboardingStep: Equatable, Sendable {
    /// Welcome screen: what StreamSnip is, and the choice to add a source or skip.
    case welcome
    /// Confirmation after a source was added (or the user chose to continue
    /// without one — sources can always be added later from Settings).
    case allSet

    /// Advances the wizard. Adding a source jumps straight to the final step;
    /// skipping from the welcome screen also lands there, with the same exit.
    static func next(from step: OnboardingStep, hasAddedSource: Bool) -> OnboardingStep {
        switch step {
        case .welcome:
            return .allSet
        case .allSet:
            return .allSet
        }
    }
}

/// Owns the onboarding wizard state. `hasCompletedOnboarding` is the
/// UserDefaults flag that keeps the wizard from reappearing; it is written
/// only when the user finishes or skips, so a crash mid-wizard retries it.
@MainActor
@Observable
final class OnboardingModel {
    private(set) var step: OnboardingStep = .welcome

    /// Whether a source was added during this run — controls the final step's copy.
    private(set) var hasAddedSource = false

    /// UserDefaults key for the completed flag.
    nonisolated static let completedKey = "hasCompletedOnboarding"

    var isComplete: Bool {
        step == .allSet
    }

    func addSourceCompleted() {
        hasAddedSource = true
        step = .allSet
    }

    /// Sheet dismissed without a confirmed add — advance, but only claim a
    /// source was added when one actually exists now.
    func addSourceDismissed(addedSource: Bool) {
        hasAddedSource = hasAddedSource || addedSource
        step = .allSet
    }

    func skip() {
        step = .allSet
    }

    /// Finishes the wizard and records the flag so it does not show again.
    func finish(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: Self.completedKey)
    }

    /// Whether onboarding should run: only on a first launch that has never
    /// finished (or skipped) the wizard.
    nonisolated static func shouldShow(defaults: UserDefaults = .standard) -> Bool {
        !defaults.bool(forKey: completedKey)
    }
}
