//
//  JellyfinAPITests.swift
//  StreamSnipTests
//
//  Unit tests for Jellyfin request building and response mapping (no server).
//

import Foundation
import Testing
@testable import StreamSnip

@Suite("Jellyfin API")
struct JellyfinAPITests {
    private let baseURL = URL(string: "https://jellyfin.example:8096")!

    @Test("Authorization header format")
    func authorizationHeader() {
        #expect(JellyfinAPI.authorizationHeader(token: "abc123") == "MediaBrowser Token=\"abc123\"")
    }

    @Test("Emby authorization header carries client and device id")
    func embyAuthorizationHeader() {
        let header = JellyfinAPI.embyAuthorizationHeader(deviceID: "device-1")
        #expect(header.contains("Client=\"StreamSnip\""))
        #expect(header.contains("DeviceId=\"device-1\""))
    }

    @Test("Authenticate-by-name request targets the login endpoint with credentials")
    func authenticateByNameRequest() throws {
        let request = try JellyfinAPI.authenticateByNameRequest(
            baseURL: baseURL,
            username: "user",
            password: "pass",
            deviceID: "device-1"
        )
        #expect(request.url?.path.hasSuffix("/Users/AuthenticateByName") == true)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "X-Emby-Authorization")?.contains("DeviceId=\"device-1\"") == true)
        let body = try #require(request.httpBody)
        let decoded = try JSONDecoder().decode(JellyfinAuthRequest.self, from: body)
        #expect(decoded.username == "user")
        #expect(decoded.pw == "pass")
    }

    @Test("HLS stream URL carries media source and key")
    func hlsStreamURL() throws {
        let url = JellyfinAPI.hlsStreamURL(baseURL: baseURL, itemID: "item1", mediaSourceID: "src1", token: "tok")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path.hasSuffix("/Videos/item1/master.m3u8"))
        let names = components.queryItems?.map(\.name) ?? []
        #expect(names.contains("MediaSourceId"))
        #expect(names.contains("api_key"))
    }

    @Test("Direct stream URL is static and container-suffixed")
    func directStreamURL() throws {
        let url = JellyfinAPI.directStreamURL(baseURL: baseURL, itemID: "item1", mediaSourceID: "src1", container: "mp4", token: "tok")
        #expect(url.path.hasSuffix("/Videos/item1/stream.mp4"))
        #expect(url.query?.contains("static=true") == true)
    }

    @Test("Item duration converts 100ns ticks to seconds")
    func tickConversion() throws {
        // 90 seconds = 900_000_000 ticks
        let json = """
        {"Id":"i1","Name":"Item","Type":"Movie","RunTimeTicks":900000000}
        """
        let item = try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))
        #expect(item.durationSeconds == 90)
    }

    @Test("Playback position maps from user data ticks")
    func playbackPosition() throws {
        let json = """
        {"Id":"i1","Name":"Item","Type":"Episode","UserData":{"PlaybackPositionTicks":300000000}}
        """
        let item = try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))
        #expect(item.playbackPositionSeconds == 30)
    }

    @Test("Stream mapping yields HLS plus direct stream when container known")
    func streamMapping() throws {
        let json = """
        {"Id":"i1","Name":"Item","Type":"Movie","MediaSources":[{"Id":"src1","Container":"mp4,mkv","Size":1000}]}
        """
        let item = try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))
        let streams = JellyfinAPI.streams(for: item, instanceURL: baseURL, token: "tok")
        #expect(streams.count == 2)
        #expect(streams.contains { $0.format == "hls" })
        #expect(streams.contains { $0.format == "mp4" && $0.fileSize == 1000 })
    }

    @Test("Stream mapping is empty without media sources")
    func streamMappingEmpty() throws {
        let json = """
        {"Id":"i1","Name":"Item","Type":"Movie"}
        """
        let item = try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))
        #expect(JellyfinAPI.streams(for: item, instanceURL: baseURL, token: nil).isEmpty)
    }

    @Test("Credential round-trips through JSON encoding")
    func credentialEncoding() throws {
        let credential = JellyfinCredential(token: "tok", userId: "uid")
        let data = try #require(JellyfinCredentialsManager.encode(credential))
        #expect(JellyfinCredentialsManager.decode(data) == credential)
    }

    @Test("Jellyfin items map to federated videos with the jellyfin provider")
    func videoMapping() throws {
        let json = """
        {"Id":"i1","Name":"Movie","Type":"Movie","RunTimeTicks":600000000,"ImageTags":{"Primary":"tag1"}}
        """
        let item = try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))
        let video = item.toVideo(instanceURL: baseURL)
        #expect(video.id.source == .federated(provider: ContentSource.jellyfinProvider, instance: baseURL))
        #expect(video.duration == 60)
        #expect(video.thumbnails.first?.url.absoluteString.contains("Items/i1/Images/Primary") == true)
    }
}
