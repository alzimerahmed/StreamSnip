//
//  DownloadLiveActivity.swift
//  StreamSnip
//
//  Live Activity surfacing an active download's progress on the Lock Screen
//  and Dynamic Island. iOS only; ActivityKit needs no new target.
//

#if os(iOS)
import ActivityKit
import Foundation

/// The attributes of the download Live Activity. One activity runs per app
/// launch, tracking the most advanced active download — a queue of downloads
/// is summarized rather than shown one activity per file.
struct DownloadActivityAttributes: ActivityAttributes {
    /// Mutable progress state.
    struct ContentState: Codable, Hashable {
        var title: String
        var progress: Double
        var speedBytesPerSecond: Int64
        var isFinished: Bool
    }

    /// Static across the activity's lifetime.
    let videoID: String
}

/// Starts, updates and ends the download Live Activity. A no-op everywhere
/// ActivityKit is unavailable (activity authorization denied, simulator
/// without support) — failures log and stop, never throwing into the
/// download pipeline.
@MainActor
final class DownloadLiveActivityController {
    static let shared = DownloadLiveActivityController()

    private var activityID: String?
    /// Throttle: Live Activity updates are budgeted by the system, so mirror
    /// the download UI's cadence rather than every byte callback.
    private var lastUpdate = Date.distantPast
    private var lastProgress: Double = -1

    var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Begins (or retargets) the activity for a download that started.
    func start(downloadID: UUID, title: String, videoID: String) {
        guard isEnabled else { return }
        end()

        do {
            let activity = try Activity.request(
                attributes: DownloadActivityAttributes(videoID: videoID),
                content: .init(state: DownloadActivityAttributes.ContentState(
                    title: title,
                    progress: 0,
                    speedBytesPerSecond: 0,
                    isFinished: false
                ), staleDate: nil)
            )
            activityID = activity.id
        } catch {
            LoggingService.shared.debug("Live Activity request failed: \(error.localizedDescription)", category: .downloads)
        }
    }

    /// Mirrors progress into the activity, throttled to 1% deltas or 2s.
    func update(title: String, progress: Double, speedBytesPerSecond: Int64) {
        guard isEnabled, activityID != nil else { return }
        let now = Date()
        guard abs(progress - lastProgress) >= 0.01 || now.timeIntervalSince(lastUpdate) >= 2 else { return }
        lastUpdate = now
        lastProgress = progress

        Task {
            for activity in Activity<DownloadActivityAttributes>.activities {
                await activity.update(.init(state: .init(
                    title: title,
                    progress: progress,
                    speedBytesPerSecond: speedBytesPerSecond,
                    isFinished: false
                ), staleDate: nil))
            }
        }
    }

    /// Ends the activity with a completed state.
    func finish(title: String, succeeded: Bool) {
        guard isEnabled else { return }
        let id = activityID
        activityID = nil
        lastProgress = -1
        Task {
            for activity in Activity<DownloadActivityAttributes>.activities where activity.id == id {
                await activity.end(.init(state: .init(
                    title: title,
                    progress: succeeded ? 1 : 0,
                    speedBytesPerSecond: 0,
                    isFinished: true
                ), staleDate: nil), dismissalPolicy: .after(.now + 4))
            }
        }
    }

    /// Ends the activity immediately (app teardown, download removed).
    func end() {
        guard isEnabled else { return }
        activityID = nil
        lastProgress = -1
        Task {
            for activity in Activity<DownloadActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
        }
    }
}
#endif
