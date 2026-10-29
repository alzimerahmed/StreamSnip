//
//  SegmentDownloadTests.swift
//  StreamSnipTests
//
//  Unit tests for clip segment byte-range math and stream selection.
//

import Foundation
import Testing
@testable import StreamSnip

@Suite("Segment download math")
struct SegmentDownloadTests {
    @Test("Proportional mapping across a 100-byte, 100-second file")
    func proportionalMapping() {
        let range = SegmentByteRangeCalculator.byteRange(
            startSeconds: 10, endSeconds: 20, duration: 100, fileSize: 100
        )
        #expect(range == SegmentByteRange(start: 10, end: 20))
        #expect(range?.length == 11)
    }

    @Test("Range is clamped to the file")
    func clamping() {
        let range = SegmentByteRangeCalculator.byteRange(
            startSeconds: 0, endSeconds: 500, duration: 100, fileSize: 100
        )
        #expect(range?.end == 99)
    }

    @Test("Zero duration or file size is rejected")
    func invalidInputs() {
        #expect(SegmentByteRangeCalculator.byteRange(startSeconds: 0, endSeconds: 5, duration: 0, fileSize: 100) == nil)
        #expect(SegmentByteRangeCalculator.byteRange(startSeconds: 0, endSeconds: 5, duration: 100, fileSize: 0) == nil)
    }

    @Test("Empty or inverted span is rejected")
    func emptySpan() {
        #expect(SegmentByteRangeCalculator.byteRange(startSeconds: 10, endSeconds: 10, duration: 100, fileSize: 100) == nil)
        #expect(SegmentByteRangeCalculator.byteRange(startSeconds: 20, endSeconds: 10, duration: 100, fileSize: 100) == nil)
    }

    @Test("Negative start clamps to zero")
    func negativeStart() {
        let range = SegmentByteRangeCalculator.byteRange(
            startSeconds: -5, endSeconds: 10, duration: 100, fileSize: 100
        )
        #expect(range?.start == 0)
    }

    @Test("Best stream selection skips adaptive and size-less streams")
    func bestStreamSelection() {
        let hls = Stream(url: URL(string: "https://example.com/a.m3u8")!, format: "hls")
        let small = Stream(
            url: URL(string: "https://example.com/s.mp4")!,
            resolution: StreamResolution(width: 0, height: 360),
            format: "mp4",
            fileSize: 1000
        )
        let large = Stream(
            url: URL(string: "https://example.com/l.mp4")!,
            resolution: StreamResolution(width: 0, height: 1080),
            format: "mp4",
            fileSize: 4000
        )
        let noSize = Stream(url: URL(string: "https://example.com/n.mp4")!, format: "mp4")

        let best = ClipSegmentDownloader.bestProgressiveStream(in: [hls, small, large, noSize])
        #expect(best?.url == large.url)
    }

    @Test("Selection returns nil when only adaptive streams exist")
    func adaptiveOnly() {
        let hls = Stream(url: URL(string: "https://example.com/a.m3u8")!, format: "hls")
        #expect(ClipSegmentDownloader.bestProgressiveStream(in: [hls]) == nil)
    }
}
