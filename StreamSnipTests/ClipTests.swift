//
//  ClipTests.swift
//  StreamSnipTests
//
//  Unit tests for clip model validation, timestamp math and store queries.
//

import Foundation
import SwiftData
import Testing
@testable import StreamSnip

@Suite("Clip model")
struct ClipModelTests {
    @Test("Valid range passes validation")
    func validRange() {
        #expect(Clip.validate(start: 10, end: 20) == nil)
        #expect(Clip.validate(start: 0, end: 1) == nil)
    }

    @Test("Out-point before in-point fails")
    func reversedRange() {
        #expect(Clip.validate(start: 20, end: 10) != nil)
        #expect(Clip.validate(start: 10, end: 10) != nil)
    }

    @Test("Sub-minimum range fails")
    func tooShort() {
        #expect(Clip.validate(start: 1.0, end: 1.0 + ClipLimits.minimumDuration - 0.01) != nil)
        #expect(Clip.validate(start: 1.0, end: 1.0 + ClipLimits.minimumDuration) == nil)
    }

    @Test("Negative times fail")
    func negativeTimes() {
        #expect(Clip.validate(start: -1, end: 5) != nil)
        #expect(Clip.validate(start: 1, end: -5) != nil)
    }

    @Test("Timestamp formatting")
    func timestampFormatting() {
        #expect(Clip.formatTimestamp(0) == "0:00")
        #expect(Clip.formatTimestamp(65) == "1:05")
        #expect(Clip.formatTimestamp(3599) == "59:59")
        #expect(Clip.formatTimestamp(3600) == "1:00:00")
        #expect(Clip.formatTimestamp(3661) == "1:01:01")
    }

    @Test("Clip duration and display title")
    @MainActor
    func clipDerivedValues() throws {
        let dataManager = try DataManager(inMemory: true)
        let clip = Clip(
            videoID: "abc123",
            sourceRawValue: "global",
            globalProvider: "youtube",
            videoTitle: "Video Title",
            authorName: "Author",
            authorID: "UC1",
            videoDuration: 300,
            startSeconds: 10,
            endSeconds: 25
        )
        #expect(clip.duration == 15)
        #expect(clip.displayTitle == "Video Title")
        #expect(clip.isValid)

        clip.title = "My Snip"
        #expect(clip.displayTitle == "My Snip")

        dataManager.modelContext.insert(clip)
        #expect(clip.formattedStart == "0:10")
        #expect(clip.formattedEnd == "0:25")
    }
}

@Suite("Clip share formats")
struct ClipShareTests {
    private func makeClip(source: String = "global", provider: String? = "youtube") -> Clip {
        Clip(
            videoID: "abc123",
            sourceRawValue: source,
            globalProvider: provider,
            videoTitle: "Video Title",
            authorName: "Author",
            authorID: "UC1",
            videoDuration: 300,
            startSeconds: 90,
            endSeconds: 120
        )
    }

    @Test("YouTube clip shares a youtu.be timestamp link")
    func youtubeTimestampLink() {
        let link = ClipShare.videoTimestampLink(for: makeClip())
        #expect(link?.absoluteString == "https://youtu.be/abc123?t=90")
    }

    @Test("Non-YouTube clip falls back to the clip deep link")
    func nonYouTubeLink() {
        let clip = makeClip(source: "federated", provider: nil)
        let link = ClipShare.videoTimestampLink(for: clip)
        #expect(link?.absoluteString == "streamsnip://clip/\(clip.id.uuidString)")
    }

    @Test("Timestamp parameter uses 1h2m3s form")
    func timestampParameter() {
        #expect(ClipShare.timestampParameter(90) == "1m30s")
        #expect(ClipShare.timestampParameter(3661) == "1h1m1s")
        #expect(ClipShare.timestampParameter(45) == "45")
        #expect(ClipShare.timestampParameter(0) == "0")
    }

    @Test("Share text contains title, range and link")
    func shareText() {
        let clip = makeClip()
        let text = ClipShare.shareText(for: clip)
        #expect(text.contains("Video Title"))
        #expect(text.contains("1:30"))
        #expect(text.contains("youtu.be"))
    }
}

@Suite("Clip store queries")
struct ClipStoreTests {
    @MainActor
    private func makeManager() throws -> DataManager {
        try DataManager(inMemory: true)
    }

    @MainActor
    private func makeClip(videoID: String, start: Double = 0, end: Double = 10) -> Clip {
        Clip(
            videoID: videoID,
            sourceRawValue: "global",
            globalProvider: "youtube",
            videoTitle: "Video \(videoID)",
            authorName: "Author",
            authorID: "UC1",
            videoDuration: 300,
            startSeconds: start,
            endSeconds: end
        )
    }

    @Test("Added clips are fetched most recent first")
    @MainActor
    func addAndFetch() throws {
        let dataManager = try makeManager()
        let older = makeClip(videoID: "one")
        let newer = makeClip(videoID: "two")
        dataManager.addClip(older)
        Thread.sleep(forTimeInterval: 0.01)
        dataManager.addClip(newer)

        let clips = dataManager.clips()
        #expect(clips.count == 2)
        #expect(clips.first?.videoID == "two")
    }

    @Test("clips(forVideoID:) filters and orders by in-point")
    @MainActor
    func fetchForVideo() throws {
        let dataManager = try makeManager()
        dataManager.addClip(makeClip(videoID: "v1", start: 60, end: 70))
        dataManager.addClip(makeClip(videoID: "v1", start: 10, end: 20))
        dataManager.addClip(makeClip(videoID: "v2", start: 0, end: 5))

        let clips = dataManager.clips(forVideoID: "v1")
        #expect(clips.count == 2)
        #expect(clips[0].startSeconds == 10)
        #expect(clips[1].startSeconds == 60)
    }

    @Test("Removing a clip deletes it")
    @MainActor
    func removeClip() throws {
        let dataManager = try makeManager()
        let clip = makeClip(videoID: "v1")
        dataManager.addClip(clip)
        #expect(dataManager.clips().count == 1)

        dataManager.removeClip(clip)
        #expect(dataManager.clips().isEmpty)
    }

    @Test("clip(forID:) round-trips")
    @MainActor
    func fetchByID() throws {
        let dataManager = try makeManager()
        let clip = makeClip(videoID: "v1")
        dataManager.addClip(clip)
        #expect(dataManager.clip(forID: clip.id)?.videoID == "v1")
    }

    @Test("Collections group clips")
    @MainActor
    func collections() throws {
        let dataManager = try makeManager()
        let clip = makeClip(videoID: "v1")
        dataManager.addClip(clip)
        let collection = dataManager.addClipCollection(name: "Favorites")

        dataManager.addClip(clip, to: collection)
        #expect((dataManager.clip(forID: clip.id)?.collections ?? []).contains { $0.id == collection.id })

        dataManager.removeClip(clip, from: collection)
        #expect((dataManager.clip(forID: clip.id)?.collections ?? []).isEmpty)

        dataManager.removeClipCollection(collection)
        #expect(dataManager.clipCollections().isEmpty)
        #expect(dataManager.clips().count == 1)
    }
}

@Suite("Clip capture controller")
struct ClipCaptureControllerTests {
    @Test("Range text reflects marks")
    @MainActor
    func markedRange() throws {
        let dataManager = try DataManager(inMemory: true)
        let httpClient = HTTPClient()
        let player = PlayerService(
            httpClient: httpClient,
            contentService: ContentService(httpClient: httpClient, basicAuthCredentialsManager: BasicAuthCredentialsManager()),
            dataManager: dataManager
        )
        let controller = ClipCaptureController(playerService: player, dataManager: dataManager)

        #expect(controller.markedRangeText == nil)
        #expect(!controller.canSave)
        controller.clear()
    }
}
