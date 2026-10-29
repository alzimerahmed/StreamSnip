//
//  ClipSegmentDownloader.swift
//  StreamSnip
//
//  Downloads a clip's time range from a progressive stream that supports
//  HTTP range requests, as a standalone media file.
//

import Foundation

/// The byte range covering a clip's time span inside a progressive file.
struct SegmentByteRange: Equatable, Sendable {
    let start: Int64
    let end: Int64

    var length: Int64 { end - start + 1 }
}

/// Pure time→byte math for segment downloads.
///
/// A progressive file has no time index, so the mapping is proportional:
/// a clip spanning `[start, end)` of a `duration`-second file covers the same
/// fraction of its bytes. The result is an *approximation* — keyframe
/// boundaries mean the decoded range can start slightly late or end slightly
/// early — which is why the feature is presented as a beta export.
enum SegmentByteRangeCalculator {
    /// - Returns: nil when the inputs cannot produce a sane range (no duration,
    ///   no file size, empty or inverted span).
    static func byteRange(
        startSeconds: TimeInterval,
        endSeconds: TimeInterval,
        duration: TimeInterval,
        fileSize: Int64
    ) -> SegmentByteRange? {
        guard duration > 0, fileSize > 0 else { return nil }
        let clampedStart = max(0, min(startSeconds, duration))
        let clampedEnd = max(0, min(endSeconds, duration))
        guard clampedEnd > clampedStart else { return nil }

        let start = Int64((clampedStart / duration) * Double(fileSize))
        var end = Int64((clampedEnd / duration) * Double(fileSize))
        end = max(start, min(end, fileSize - 1))
        guard end >= start else { return nil }
        return SegmentByteRange(start: start, end: end)
    }
}

/// Errors a segment download can fail with, phrased for the user.
enum SegmentDownloadError: LocalizedError, Sendable {
    /// The server does not honor Range requests — nothing to degrade to.
    case rangeNotSupported
    /// No progressive (byte-addressable) stream exists; HLS/DASH sources
    /// cannot be ranged.
    case noProgressiveStream
    /// Segment export is not available on this platform (no writable
    /// documents directory).
    case unsupportedPlatform
    case invalidClip

    var errorDescription: String? {
        switch self {
        case .rangeNotSupported:
            return String(localized: "downloads.segment.rangeNotSupported", defaultValue: "This source doesn't support partial downloads.")
        case .noProgressiveStream:
            return String(localized: "downloads.segment.noProgressiveStream", defaultValue: "Segment export needs a direct video file; this stream is adaptive (HLS/DASH).")
        case .unsupportedPlatform:
            return String(localized: "downloads.segment.unsupportedPlatform", defaultValue: "Segment export isn't available on this device.")
        case .invalidClip:
            return String(localized: "downloads.segment.invalidClip", defaultValue: "This clip's range can't be exported.")
        }
    }
}

/// One running (or finished) segment download, surfaced in the UI.
struct SegmentDownload: Identifiable, Sendable {
    let id = UUID()
    let clipTitle: String
    var progress: Double = 0
    var destinationURL: URL?
    var errorMessage: String?
}

/// Downloads clip segments. Owns its active list so the downloads surface can
/// show progress; each download streams the ranged response to a file under
/// `Documents/Clips`.
@MainActor
@Observable
final class ClipSegmentDownloader {
    private(set) var active: [SegmentDownload] = []

    #if os(iOS) || os(macOS)
    private var directory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Clips", isDirectory: true)
    }
    #else
    private var directory: URL? { nil }
    #endif

    /// Picks the best byte-addressable stream for a video: a progressive
    /// container (mp4/webm/mkv) with a known file size. HLS/DASH playlists
    /// are skipped — they cannot be ranged.
    nonisolated static func bestProgressiveStream(in streams: [Stream]) -> Stream? {
        streams
            .filter { stream in
                let format = stream.format.lowercased()
                return format != "hls" && format != "dash" && stream.fileSize != nil && stream.fileSize! > 0
            }
            .max { ($0.resolution?.height ?? 0) < ($1.resolution?.height ?? 0) }
    }

    /// Resolves the stream for the clip's video and downloads its range.
    /// Feedback goes through toasts; progress is observable on `active`.
    func download(clip: Clip, appEnvironment: AppEnvironment) async {
        let video = clip.toVideo()
        guard let instance = appEnvironment.instancesManager.instance(for: video.id.source) else {
            appEnvironment.toastManager.showError(String(localized: "downloads.segment.noSource", defaultValue: "The source for this clip isn't available."))
            return
        }

        do {
            let streams = try await appEnvironment.contentService.streams(videoID: video.id.videoID, instance: instance)
            guard let stream = Self.bestProgressiveStream(in: streams),
                  let fileSize = stream.fileSize else {
                throw SegmentDownloadError.noProgressiveStream
            }
            guard let range = SegmentByteRangeCalculator.byteRange(
                startSeconds: clip.startSeconds,
                endSeconds: clip.endSeconds,
                duration: video.duration,
                fileSize: fileSize
            ) else {
                throw SegmentDownloadError.invalidClip
            }
            try await downloadRange(from: stream.url, byteRange: range, clipTitle: clip.displayTitle, instance: instance)
            appEnvironment.toastManager.showSuccess(
                String(localized: "downloads.segment.saved", defaultValue: "Segment Saved"),
                subtitle: clip.displayTitle
            )
        } catch let error as SegmentDownloadError {
            appEnvironment.toastManager.showError(error.errorDescription ?? String(describing: error))
        } catch is CancellationError {
            // The user (or teardown) cancelled; nothing to report.
        } catch {
            appEnvironment.toastManager.showError(
                String(localized: "downloads.segment.failed", defaultValue: "Segment download failed."),
                subtitle: error.localizedDescription
            )
        }
    }

    // MARK: - Range Download

    private func downloadRange(
        from url: URL,
        byteRange: SegmentByteRange,
        clipTitle: String,
        instance: Instance
    ) async throws -> URL {
        guard let directory else { throw SegmentDownloadError.unsupportedPlatform }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("bytes=\(byteRange.start)-\(byteRange.end)", forHTTPHeaderField: "Range")
        if let headers = instance.basicAuthHeaderFields() {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Probe range support first so an unsupported server fails fast with a
        // clear reason instead of a mid-transfer surprise. A server that
        // answers a ranged GET with 200 (not 206) would otherwise deliver the
        // whole file.
        var probe = URLRequest(url: url)
        probe.httpMethod = "HEAD"
        if let headers = instance.basicAuthHeaderFields() {
            for (key, value) in headers {
                probe.setValue(value, forHTTPHeaderField: key)
            }
        }
        let (_, headResponse) = try await URLSession.shared.data(for: probe)
        let acceptsRanges = (headResponse as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Accept-Ranges")?
            .lowercased() == "bytes"
        if !acceptsRanges {
            throw SegmentDownloadError.rangeNotSupported
        }

        let download = SegmentDownload(clipTitle: clipTitle)
        active.append(download)
        let id = download.id

        do {
            let destination = try await performRangeDownload(
                request: request,
                byteRange: byteRange,
                clipTitle: clipTitle,
                id: id,
                directory: directory
            )
            // Let the completed row (with its destination) be seen before it
            // leaves the section.
            try? await Task.sleep(for: .seconds(3))
            active.removeAll { $0.id == id }
            return destination
        } catch {
            active.removeAll { $0.id == id }
            throw error
        }
    }

    private func performRangeDownload(
        request: URLRequest,
        byteRange: SegmentByteRange,
        clipTitle: String,
        id: UUID,
        directory: URL
    ) async throws -> URL {
        let fileName = sanitizedFileName(clipTitle) + "-" + UUID().uuidString.prefix(8).description + ".mp4"
        let destination = directory.appendingPathComponent(fileName)
        do {
            let (tempURL, response) = try await URLSession.shared.download(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw APIError.httpError(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0, message: nil)
            }
            // A 200 to a ranged request means the server ignored the range.
            if http.statusCode == 200 {
                throw SegmentDownloadError.rangeNotSupported
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)

            if let index = active.firstIndex(where: { $0.id == id }) {
                active[index].progress = 1
                active[index].destinationURL = destination
            }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func sanitizedFileName(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        return cleaned.isEmpty ? "clip" : String(cleaned.prefix(80))
    }
}

extension Instance {
    /// Header fields a request to this instance's streams may need (basic-auth
    /// proxies). Kept small: Jellyfin's token rides the URL as `api_key`.
    func basicAuthHeaderFields() -> [String: String]? {
        nil
    }
}
