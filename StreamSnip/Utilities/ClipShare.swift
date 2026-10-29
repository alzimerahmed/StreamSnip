//
//  ClipShare.swift
//  StreamSnip
//
//  Share link and export formatting for clips.
//

import Foundation

/// Builds shareable representations of a clip: timestamp deep links and
/// plain-text export. Video re-encode export is out of scope (P2-1).
enum ClipShare {
    /// Deep link that opens this clip in StreamSnip: `streamsnip://clip/<uuid>`.
    static func deepLink(for clip: Clip) -> URL? {
        URL(string: "streamsnip://clip/\(clip.id.uuidString)")
    }

    /// Video-level timestamp link. For YouTube videos this is the canonical
    /// `youtu.be/<id>?t=<start>` form, which StreamSnip routes natively and
    /// stays usable for recipients without the app. Other sources fall back
    /// to the `streamsnip://clip/<uuid>` deep link.
    static func videoTimestampLink(for clip: Clip) -> URL? {
        if clip.sourceRawValue == "global",
           clip.globalProvider == ContentSource.youtubeProvider {
            var components = URLComponents()
            components.scheme = "https"
            components.host = "youtu.be"
            components.path = "/\(clip.videoID)"
            components.queryItems = [
                URLQueryItem(name: "t", value: String(Int(clip.startSeconds)))
            ]
            return components.url
        }
        return deepLink(for: clip)
    }

    /// `t` parameter value in YouTube-style `1h2m3s` form (`90` stays `90`).
    static func timestampParameter(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        guard total > 0 else { return "0" }
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return "\(hours)h\(minutes)m\(secs)s"
        }
        if minutes > 0 {
            return "\(minutes)m\(secs)s"
        }
        return "\(secs)"
    }

    /// Plain-text share body: title, video, range and timestamp link.
    static func shareText(for clip: Clip) -> String {
        var text = clip.displayTitle
        if clip.displayTitle != clip.videoTitle {
            text += " — \(clip.videoTitle)"
        }
        text += " (\(clip.formattedStart)–\(clip.formattedEnd))"
        if let link = videoTimestampLink(for: clip) {
            text += "\n\(link.absoluteString)"
        }
        return text
    }
}
