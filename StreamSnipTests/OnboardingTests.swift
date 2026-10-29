//
//  OnboardingTests.swift
//  StreamSnipTests
//
//  Unit tests for the first-run onboarding state machine.
//

import Foundation
import Testing
@testable import StreamSnip

@Suite("Onboarding state")
@MainActor
struct OnboardingTests {
    @Test("Welcome advances to all-set regardless of source outcome")
    func stepProgression() {
        #expect(OnboardingStep.next(from: .welcome, hasAddedSource: true) == .allSet)
        #expect(OnboardingStep.next(from: .welcome, hasAddedSource: false) == .allSet)
        #expect(OnboardingStep.next(from: .allSet, hasAddedSource: false) == .allSet)
    }

    @Test("Should show only when the completed flag is unset")
    func shouldShowFlag() {
        let defaults = UserDefaults(suiteName: "OnboardingTests")!
        defaults.removeObject(forKey: OnboardingModel.completedKey)
        #expect(OnboardingModel.shouldShow(defaults: defaults))

        defaults.set(true, forKey: OnboardingModel.completedKey)
        #expect(!OnboardingModel.shouldShow(defaults: defaults))
    }

    @Test("Finish writes the completed flag")
    func finishWritesFlag() {
        let defaults = UserDefaults(suiteName: "OnboardingFinishTests")!
        defaults.removeObject(forKey: OnboardingModel.completedKey)

        let model = OnboardingModel()
        model.skip()
        model.finish(defaults: defaults)
        #expect(defaults.bool(forKey: OnboardingModel.completedKey))
    }

    @Test("Adding a source lands on the final step with source copy")
    @Test("Add-source path")
    func addSourcePath() {
        let model = OnboardingModel()
        #expect(model.step == .welcome)
        model.addSourceCompleted()
        #expect(model.isComplete)
        #expect(model.hasAddedSource)
    }

    @Test("Backing out of add-source without adding claims no source")
    func addSourceDismissedWithoutSource() {
        let model = OnboardingModel()
        model.addSourceDismissed(addedSource: false)
        #expect(model.isComplete)
        #expect(!model.hasAddedSource)
    }

    @Test("Backing out after adding claims a source")
    func addSourceDismissedWithSource() {
        let model = OnboardingModel()
        model.addSourceDismissed(addedSource: true)
        #expect(model.isComplete)
        #expect(model.hasAddedSource)
    }
}
