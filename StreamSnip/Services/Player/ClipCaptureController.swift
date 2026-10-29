//
//  ClipCaptureController.swift
//  StreamSnip
//
//  In/out marking state for clip capture, owned by AppEnvironment.
//

import Foundation

/// Owns the in/out marking state for the player clip capture flow and
/// persists finished clips through DataManager.
@MainActor
@Observable
final class ClipCaptureController {
    // MARK: - State

    /// Marked in-point in seconds, if set.
    private(set) var inPoint: TimeInterval?

    /// Marked out-point in seconds, if set.
    private(set) var outPoint: TimeInterval?

    /// Last validation failure to surface in the UI.
    private(set) var errorMessage: String?

    // MARK: - Dependencies

    private weak var playerService: PlayerService?
    private weak var dataManager: DataManager?

    init(playerService: PlayerService, dataManager: DataManager) {
        self.playerService = playerService
        self.dataManager = dataManager
    }

    // MARK: - Computed State

    /// Whether a clip can be captured right now (a video is loaded).
    var canCapture: Bool {
        playerService?.state.currentVideo != nil
    }

    /// Whether both marks are set and the range validates.
    var canSave: Bool {
        guard let inPoint, let outPoint else { return false }
        return Clip.validate(start: inPoint, end: outPoint) == nil
    }

    /// Current marked range description for display.
    var markedRangeText: String? {
        guard inPoint != nil || outPoint != nil else { return nil }
        let start = inPoint.map(Clip.formatTimestamp) ?? "–"
        let end = outPoint.map(Clip.formatTimestamp) ?? "–"
        return "\(start) → \(end)"
    }

    // MARK: - Marking

    /// Marks the in-point at the current playback position.
    func markIn() {
        guard let time = playerService?.state.currentTime else { return }
        inPoint = time
        errorMessage = nil
        validatePair()
    }

    /// Marks the out-point at the current playback position.
    func markOut() {
        guard let time = playerService?.state.currentTime else { return }
        outPoint = time
        errorMessage = nil
        validatePair()
    }

    /// Clears both marks.
    func clear() {
        inPoint = nil
        outPoint = nil
        errorMessage = nil
    }

    /// Saves the marked range as a clip and clears the marks.
    /// - Returns: the saved clip, or nil when the range is invalid or no video is loaded.
    @discardableResult
    func saveClip(title: String = "", note: String? = nil) -> Clip? {
        guard let video = playerService?.state.currentVideo,
              let inPoint, let outPoint else {
            errorMessage = String(localized: "clip.error.noMarks", defaultValue: "Set an in-point and an out-point first")
            return nil
        }
        let start = min(inPoint, outPoint)
        let end = max(inPoint, outPoint)
        if let failure = Clip.validate(start: start, end: end) {
            errorMessage = failure
            return nil
        }

        let clip = Clip.from(
            video: video,
            startSeconds: start,
            endSeconds: end,
            title: title,
            note: note
        )
        dataManager?.addClip(clip)
        clear()
        return clip
    }

    // MARK: - Private

    private func validatePair() {
        guard let inPoint, let outPoint else { return }
        errorMessage = Clip.validate(start: min(inPoint, outPoint), end: max(inPoint, outPoint))
    }
}
