//
//  Clip.swift
//  StreamSnip
//
//  SwiftData models for captured clips ("snips") and their collections.
//

import Foundation
import SwiftData

/// Minimum clip length in seconds. Anything shorter is rejected as a marking mistake.
enum ClipLimits {
    static let minimumDuration: TimeInterval = 0.5
}

/// A saved clip: an in/out range on a video, captured during playback.
@Model
final class Clip {
    // MARK: - Identity

    /// Stable identity, also the CloudKit record name component.
    var id: UUID = UUID()

    // MARK: - Video Identity

    /// The video ID string (YouTube ID or PeerTube UUID).
    var videoID: String = ""

    /// The content source raw value for encoding ("global", "federated", "extracted").
    var sourceRawValue: String = "global"

    /// For global sources: the provider name (e.g., "youtube").
    var globalProvider: String?

    /// For PeerTube: the instance URL string.
    var instanceURLString: String?

    /// For PeerTube: the UUID.
    var peertubeUUID: String?

    /// For external sources: the extractor name.
    var externalExtractor: String?

    /// For external sources: the original URL for re-extraction.
    var externalURLString: String?

    // MARK: - Video Metadata (cached for offline display)

    /// The video title.
    var videoTitle: String = ""

    /// The channel/author name.
    var authorName: String = ""

    /// The channel/author ID.
    var authorID: String = ""

    /// Full video duration in seconds.
    var videoDuration: TimeInterval = 0

    /// Thumbnail URL string.
    var thumbnailURLString: String?

    // MARK: - Clip Data

    /// User-facing clip title; empty falls back to the video title.
    var title: String = ""

    /// In-point in seconds.
    var startSeconds: Double = 0

    /// Out-point in seconds.
    var endSeconds: Double = 0

    /// When this clip was created.
    var createdAt: Date = Date()

    /// Optional user note.
    var note: String?

    /// When the note was last modified.
    var noteModifiedAt: Date?

    /// Collections this clip belongs to.
    var collections: [ClipCollection]? = []

    // MARK: - Initialization

    init(
        videoID: String,
        sourceRawValue: String,
        globalProvider: String? = nil,
        instanceURLString: String? = nil,
        peertubeUUID: String? = nil,
        externalExtractor: String? = nil,
        externalURLString: String? = nil,
        videoTitle: String,
        authorName: String,
        authorID: String,
        videoDuration: TimeInterval,
        thumbnailURLString: String? = nil,
        title: String = "",
        startSeconds: Double,
        endSeconds: Double,
        note: String? = nil
    ) {
        self.id = UUID()
        self.videoID = videoID
        self.sourceRawValue = sourceRawValue
        self.globalProvider = globalProvider
        self.instanceURLString = instanceURLString
        self.peertubeUUID = peertubeUUID
        self.externalExtractor = externalExtractor
        self.externalURLString = externalURLString
        self.videoTitle = videoTitle
        self.authorName = authorName
        self.authorID = authorID
        self.videoDuration = videoDuration
        self.thumbnailURLString = thumbnailURLString
        self.title = title
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.note = note
        self.createdAt = Date()
    }

    // MARK: - Computed Properties

    /// Clip length in seconds.
    var duration: TimeInterval {
        endSeconds - startSeconds
    }

    /// Display title: the clip title, or the video title when unset.
    var displayTitle: String {
        title.isEmpty ? videoTitle : title
    }

    /// The content source for this clip.
    var contentSource: ContentSource {
        if sourceRawValue == "global" {
            return .global(provider: globalProvider ?? ContentSource.youtubeProvider)
        } else if sourceRawValue == "federated",
                  let urlString = instanceURLString,
                  let url = URL(string: urlString) {
            return .federated(provider: ContentSource.peertubeProvider, instance: url)
        } else if sourceRawValue == "extracted",
                  let extractor = externalExtractor,
                  let urlString = externalURLString,
                  let url = URL(string: urlString) {
            return .extracted(extractor: extractor, originalURL: url)
        }
        return .global(provider: globalProvider ?? ContentSource.youtubeProvider)
    }

    /// The thumbnail URL if available.
    var thumbnailURL: URL? {
        thumbnailURLString.flatMap { URL(string: $0) }
    }

    /// Formatted clip duration string.
    var formattedDuration: String {
        Self.formatTimestamp(duration)
    }

    /// Formatted in-point timestamp.
    var formattedStart: String {
        Self.formatTimestamp(startSeconds)
    }

    /// Formatted out-point timestamp.
    var formattedEnd: String {
        Self.formatTimestamp(endSeconds)
    }

    /// Whether the stored range still validates against the clip rules.
    var isValid: Bool {
        Self.validate(start: startSeconds, end: endSeconds) == nil
    }

    /// Converts this clip to a Video model for playback at the in-point.
    func toVideo() -> Video {
        let videoIDObj: VideoID
        switch contentSource {
        case .global(let provider):
            videoIDObj = VideoID(source: .global(provider: provider), videoID: videoID)
        case .federated(let provider, let instance):
            videoIDObj = VideoID(source: .federated(provider: provider, instance: instance), videoID: videoID, uuid: peertubeUUID)
        case .extracted(let extractor, let originalURL):
            videoIDObj = VideoID(source: .extracted(extractor: extractor, originalURL: originalURL), videoID: videoID)
        }

        return Video(
            id: videoIDObj,
            title: videoTitle,
            description: nil,
            author: Author(id: authorID, name: authorName, thumbnailURL: nil, subscriberCount: nil),
            duration: videoDuration,
            publishedAt: nil,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: Thumbnail.fallbackChain(for: thumbnailURL),
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    // MARK: - Validation & Formatting

    /// Validates an in/out range. Returns a failure reason, or nil when valid.
    static func validate(start: TimeInterval, end: TimeInterval) -> String? {
        guard start >= 0, end >= 0 else {
            return String(localized: "clip.error.negative", defaultValue: "Clip times can't be negative")
        }
        guard end > start else {
            return String(localized: "clip.error.order", defaultValue: "The out-point must come after the in-point")
        }
        guard end - start >= ClipLimits.minimumDuration else {
            return String(localized: "clip.error.tooShort", defaultValue: "Clip is too short")
        }
        return nil
    }

    /// Formats seconds as h:mm:ss / m:ss.
    static func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Factory

extension Clip {
    /// Creates a Clip from a Video model and an in/out range.
    static func from(video: Video, startSeconds: Double, endSeconds: Double, title: String = "", note: String? = nil) -> Clip {
        let sourceRaw: String
        var provider: String?
        var instanceURL: String?
        var uuid: String?
        var extractor: String?
        var externalURL: String?

        switch video.id.source {
        case .global(let prov):
            sourceRaw = "global"
            provider = prov
        case .federated(_, let instance):
            sourceRaw = "federated"
            instanceURL = instance.absoluteString
            uuid = video.id.uuid
        case .extracted(let ext, let originalURL):
            sourceRaw = "extracted"
            extractor = ext
            externalURL = originalURL.absoluteString
        }

        return Clip(
            videoID: video.id.videoID,
            sourceRawValue: sourceRaw,
            globalProvider: provider,
            instanceURLString: instanceURL,
            peertubeUUID: uuid,
            externalExtractor: extractor,
            externalURLString: externalURL,
            videoTitle: video.title,
            authorName: video.author.name,
            authorID: video.author.id,
            videoDuration: video.duration,
            thumbnailURLString: video.bestThumbnail?.url.absoluteString,
            title: title,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            note: note
        )
    }
}

/// A named collection of clips.
@Model
final class ClipCollection {
    /// Stable identity, also the CloudKit record name component.
    var id: UUID = UUID()

    /// Collection name.
    var name: String = ""

    /// When the collection was created.
    var createdAt: Date = Date()

    /// Clips in this collection.
    @Relationship(inverse: \Clip.collections)
    var clips: [Clip]? = []

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
    }
}
