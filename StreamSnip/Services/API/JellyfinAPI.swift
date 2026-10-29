//
//  JellyfinAPI.swift
//  StreamSnip
//
//  Jellyfin server API implementation.
//  API Documentation: https://api.jellyfin.org/
//

@preconcurrency import Foundation

/// A stored Jellyfin credential: the access token from
/// `POST /Users/AuthenticateByName` plus the user id the server issued with it.
/// Most item endpoints are user-scoped, so both travel together.
struct JellyfinCredential: Codable, Equatable, Sendable {
    let token: String
    let userId: String
}

/// Jellyfin API client. Self-contained: talks to the server through the shared
/// `HTTPClient`, with the access token attached per request as
/// `Authorization: MediaBrowser Token="…"`.
actor JellyfinAPI: InstanceAPI {
    private let httpClient: HTTPClient

    /// Resolves the stored credential for an instance at call time, so a
    /// sign-in (or sign-out) between requests is picked up without rebuilding
    /// the client. `nil` when the server has no stored login — every
    /// user-scoped endpoint then degrades to anonymous behavior.
    private let credentialProvider: @Sendable (Instance) async -> JellyfinCredential?

    init(
        httpClient: HTTPClient,
        credentialProvider: @escaping @Sendable (Instance) async -> JellyfinCredential? = { _ in nil }
    ) {
        self.httpClient = httpClient
        self.credentialProvider = credentialProvider
    }

    // MARK: - Request Building (pure, testable)

    /// The `Authorization` header value Jellyfin expects for an authenticated
    /// request. Kept static and pure so request building is unit-testable.
    nonisolated static func authorizationHeader(token: String) -> String {
        "MediaBrowser Token=\"\(token)\""
    }

    /// The `X-Emby-Authorization` header every Jellyfin request should carry,
    /// including the login POST itself.
    nonisolated static func embyAuthorizationHeader(
        client: String = "StreamSnip",
        device: String = "StreamSnip",
        deviceID: String,
        version: String = "1.0"
    ) -> String {
        "MediaBrowser Client=\"\(client)\", Device=\"\(device)\", DeviceId=\"\(deviceID)\", Version=\"\(version)\""
    }

    /// Builds the authenticate-by-name request. Pure so tests can assert the
    /// path, method and body without a server.
    nonisolated static func authenticateByNameRequest(
        baseURL: URL,
        username: String,
        password: String,
        deviceID: String
    ) throws -> URLRequest {
        var request = try GenericEndpoint.post(
            "/Users/AuthenticateByName",
            body: JellyfinAuthRequest(username: username, pw: password)
        )
        .urlRequest(baseURL: baseURL)
        request.setValue(
            embyAuthorizationHeader(deviceID: deviceID),
            forHTTPHeaderField: "X-Emby-Authorization"
        )
        return request
    }

    /// The HLS master playlist URL for an item's media source. Pure.
    nonisolated static func hlsStreamURL(
        baseURL: URL,
        itemID: String,
        mediaSourceID: String,
        token: String
    ) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("Videos/\(itemID)/master.m3u8"), resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "MediaSourceId", value: mediaSourceID),
            URLQueryItem(name: "api_key", value: token)
        ]
        return components?.url ?? baseURL
    }

    /// The direct-stream (remuxed container) URL for an item. Pure.
    nonisolated static func directStreamURL(
        baseURL: URL,
        itemID: String,
        mediaSourceID: String,
        container: String,
        token: String
    ) -> URL {
        var components = URLComponents(url: baseURL.appendingPathComponent("Videos/\(itemID)/stream.\(container)"), resolvingAgainstBaseURL: true)
        components?.queryItems = [
            URLQueryItem(name: "MediaSourceId", value: mediaSourceID),
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "api_key", value: token)
        ]
        return components?.url ?? baseURL
    }

    // MARK: - Authentication

    /// Authenticates by name and returns the credential to store.
    func login(username: String, password: String, instance: Instance) async throws -> JellyfinCredential {
        let deviceID = instance.id.uuidString
        let encoder = JSONEncoder()
        let body = (try? encoder.encode(JellyfinAuthRequest(username: username, pw: password))) ?? Data()
        let endpoint = GenericEndpoint(
            path: "/Users/AuthenticateByName",
            method: .post,
            headers: ["X-Emby-Authorization": Self.embyAuthorizationHeader(deviceID: deviceID)],
            body: body
        )
        let response: JellyfinAuthResponse = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return JellyfinCredential(token: response.accessToken, userId: response.user.id)
    }

    // MARK: - InstanceAPI

    /// Latest movies/episodes added to the server, newest first.
    func trending(instance: Instance) async throws -> [Video] {
        guard let credential = await credentialProvider(instance) else {
            throw APIError.unauthorized
        }
        let endpoint = GenericEndpoint.get("/Users/\(credential.userId)/Items", query: [
            "Limit": "24",
            "SortBy": "DateCreated",
            "SortOrder": "Descending",
            "Recursive": "true",
            "IncludeItemTypes": "Movie,Episode",
            "Fields": "Overview,Path,MediaSources"
        ])
        let response: JellyfinItemsPage = try await httpClient.fetch(
            endpoint,
            baseURL: instance.url,
            customHeaders: [Self.authHeaderName: Self.authorizationHeader(token: credential.token)]
        )
        return response.items.map { $0.toVideo(instanceURL: instance.url) }
    }

    /// Continue-watching items. Falls back to latest when nothing is in
    /// progress, so the home surface is never empty on an active server.
    func popular(instance: Instance) async throws -> [Video] {
        guard let credential = await credentialProvider(instance) else {
            throw APIError.unauthorized
        }
        let endpoint = GenericEndpoint.get("/Users/\(credential.userId)/Items/Resume", query: [
            "Limit": "24",
            "Recursive": "true",
            "IncludeItemTypes": "Movie,Episode",
            "Fields": "Overview,Path,MediaSources"
        ])
        let response: JellyfinItemsPage = try await httpClient.fetch(
            endpoint,
            baseURL: instance.url,
            customHeaders: [Self.authHeaderName: Self.authorizationHeader(token: credential.token)]
        )
        if !response.items.isEmpty {
            return response.items.map { $0.toVideo(instanceURL: instance.url) }
        }
        return try await trending(instance: instance)
    }

    func search(query: String, instance: Instance, page: Int, filters: SearchFilters) async throws -> SearchResult {
        guard let credential = await credentialProvider(instance) else {
            throw APIError.unauthorized
        }
        let startIndex = (page - 1) * 30
        let endpoint = GenericEndpoint.get("/Users/\(credential.userId)/Items", query: [
            "SearchTerm": query,
            "Limit": "30",
            "StartIndex": String(startIndex),
            "Recursive": "true",
            "IncludeItemTypes": "Movie,Episode,Series",
            "Fields": "Overview,MediaSources"
        ])
        let response: JellyfinItemsPage = try await httpClient.fetch(
            endpoint,
            baseURL: instance.url,
            customHeaders: [Self.authHeaderName: Self.authorizationHeader(token: credential.token)]
        )
        let videos = response.items
            .filter { $0.type != "Series" }
            .map { $0.toVideo(instanceURL: instance.url) }
        let channels = response.items
            .filter { $0.type == "Series" }
            .map { $0.toChannel(instanceURL: instance.url) }
        let hasMore = startIndex + response.items.count < response.totalRecordCount
        return SearchResult(
            videos: videos,
            channels: channels,
            playlists: [],
            orderedItems: videos.map { .video($0) } + channels.map { .channel($0) },
            nextPage: hasMore ? page + 1 : nil
        )
    }

    func video(id: String, instance: Instance) async throws -> Video {
        try await item(id: id, instance: instance).toVideo(instanceURL: instance.url)
    }

    func channel(id: String, instance: Instance) async throws -> Channel {
        try await item(id: id, instance: instance).toChannel(instanceURL: instance.url)
    }

    /// Lists the items of a library (a Jellyfin collection or folder).
    func channelVideos(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        guard let credential = await credentialProvider(instance) else {
            throw APIError.unauthorized
        }
        let startIndex = Int(continuation ?? "0") ?? 0
        let pageSize = 30
        let endpoint = GenericEndpoint.get("/Users/\(credential.userId)/Items", query: [
            "ParentId": id,
            "Limit": String(pageSize),
            "StartIndex": String(startIndex),
            "SortBy": "SortName",
            "SortOrder": "Ascending",
            "Recursive": "true",
            "IncludeItemTypes": "Movie,Episode",
            "Fields": "Overview,MediaSources"
        ])
        let response: JellyfinItemsPage = try await httpClient.fetch(
            endpoint,
            baseURL: instance.url,
            customHeaders: [Self.authHeaderName: Self.authorizationHeader(token: credential.token)]
        )
        let videos = response.items.map { $0.toVideo(instanceURL: instance.url) }
        let next = startIndex + videos.count < response.totalRecordCount ? String(startIndex + pageSize) : nil
        return ChannelVideosPage(videos: videos, continuation: next)
    }

    func playlist(id: String, instance: Instance) async throws -> Playlist {
        guard let credential = await credentialProvider(instance) else {
            throw APIError.unauthorized
        }
        let item = try await item(id: id, instance: instance)
        let itemsEndpoint = GenericEndpoint.get("/Playlists/\(id)/Items", query: [
            "UserId": credential.userId,
            "Fields": "Overview,MediaSources"
        ])
        let response: JellyfinItemsPage = try await httpClient.fetch(
            itemsEndpoint,
            baseURL: instance.url,
            customHeaders: [Self.authHeaderName: Self.authorizationHeader(token: credential.token)]
        )
        return Playlist(
            id: .federated(id, provider: ContentSource.jellyfinProvider, instance: instance.url),
            title: item.name,
            description: item.overview,
            author: nil,
            videoCount: response.totalRecordCount,
            thumbnailURL: item.thumbnailURL(instanceURL: instance.url),
            videos: response.items.map { $0.toVideo(instanceURL: instance.url) }
        )
    }

    func comments(videoID: String, instance: Instance, continuation: String?) async throws -> CommentsPage {
        CommentsPage(comments: [], continuation: nil)
    }

    func channelSearch(id: String, query: String, instance: Instance, page: Int) async throws -> ChannelSearchPage {
        ChannelSearchPage(items: [], nextPage: nil)
    }

    // MARK: - Streams

    /// Resolves the playback streams for an item: an HLS master playlist plus,
    /// when the server exposes a direct-playable container, a direct stream.
    func streams(videoID: String, instance: Instance) async throws -> [Stream] {
        let item = try await item(id: videoID, instance: instance)
        return Self.streams(for: item, instanceURL: instance.url, token: await credentialProvider(instance)?.token)
    }

    /// Pure stream mapping, testable without a server.
    nonisolated static func streams(
        for item: JellyfinItem,
        instanceURL: URL,
        token: String?
    ) -> [Stream] {
        var streams: [Stream] = []
        guard let mediaSources = item.mediaSources, !mediaSources.isEmpty else { return streams }

        for source in mediaSources {
            if let container = source.container?.split(separator: ",").first.map(String.init) {
                streams.append(Stream(
                    url: directStreamURL(
                        baseURL: instanceURL,
                        itemID: item.id,
                        mediaSourceID: source.id,
                        container: container,
                        token: token ?? ""
                    ),
                    resolution: nil,
                    format: container,
                    audioCodec: source.mediaStreams?.first { $0.type == "Audio" }?.codec,
                    fileSize: source.size,
                    mimeType: "video/\(container)"
                ))
            }
            streams.append(Stream(
                url: hlsStreamURL(
                    baseURL: instanceURL,
                    itemID: item.id,
                    mediaSourceID: source.id,
                    token: token ?? ""
                ),
                resolution: nil,
                format: "hls",
                isLive: false,
                mimeType: "application/x-mpegURL"
            ))
        }
        return streams
    }

    // MARK: - Private

    nonisolated static let authHeaderName = "Authorization"

    private func item(id: String, instance: Instance) async throws -> JellyfinItem {
        guard let credential = await credentialProvider(instance) else {
            throw APIError.unauthorized
        }
        let endpoint = GenericEndpoint.get("/Users/\(credential.userId)/Items/\(id)", query: [
            "Fields": "Overview,MediaSources,Path"
        ])
        return try await httpClient.fetch(
            endpoint,
            baseURL: instance.url,
            customHeaders: [Self.authHeaderName: Self.authorizationHeader(token: credential.token)]
        )
    }
}

// MARK: - Request/Response Models

struct JellyfinAuthRequest: Encodable, Sendable {
    let username: String
    let pw: String
}

struct JellyfinAuthResponse: Decodable, Sendable {
    let accessToken: String
    let user: JellyfinAuthUser
}

struct JellyfinAuthUser: Decodable, Sendable {
    let id: String
}

struct JellyfinItemsPage: Decodable, Sendable {
    let items: [JellyfinItem]
    let totalRecordCount: Int

    private enum CodingKeys: String, CodingKey {
        case items = "Items"
        case totalRecordCount = "TotalRecordCount"
    }
}

/// A Jellyfin `BaseItemDto`, reduced to the fields StreamSnip consumes.
struct JellyfinItem: Decodable, Sendable {
    let id: String
    let name: String
    let type: String
    let overview: String?
    let duration: Int?
    let premiereDate: String?
    let dateCreated: String?
    let communityRating: Double?
    let userData: JellyfinUserData?
    let mediaSources: [JellyfinMediaSource]?
    let imageTags: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case overview = "Overview"
        case duration = "RunTimeTicks"
        case premiereDate = "PremiereDate"
        case dateCreated = "DateCreated"
        case communityRating = "CommunityRating"
        case userData = "UserData"
        case mediaSources = "MediaSources"
        case imageTags = "ImageTags"
    }

    /// Jellyfin durations are 100ns ticks.
    nonisolated var durationSeconds: TimeInterval {
        TimeInterval(duration ?? 0) / 10_000_000
    }

    /// Parses a Jellyfin ISO-8601 date, tolerating the fractional seconds some
    /// servers emit.
    nonisolated static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string)
    }

    nonisolated var playbackPositionSeconds: TimeInterval? {
        guard let ticks = userData?.playbackPositionTicks, ticks > 0 else { return nil }
        return TimeInterval(ticks) / 10_000_000
    }

    nonisolated func thumbnailURL(instanceURL: URL) -> URL? {
        guard let tag = imageTags?["Primary"] else { return nil }
        return instanceURL.appendingPathComponent("Items/\(id)/Images/Primary?tag=\(tag)&maxWidth=640")
    }

    nonisolated func toVideo(instanceURL: URL) -> Video {
        let publishedAt = (premiereDate ?? dateCreated).flatMap { Self.parseDate($0) }

        return Video(
            id: .federated(id, provider: ContentSource.jellyfinProvider, instance: instanceURL),
            title: name,
            description: overview,
            author: Author(
                id: id,
                name: type,
                thumbnailURL: nil,
                instance: instanceURL
            ),
            duration: durationSeconds,
            publishedAt: publishedAt,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: thumbnailURL(instanceURL: instanceURL).map { [Thumbnail(url: $0, quality: .medium)] } ?? [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    nonisolated func toChannel(instanceURL: URL) -> Channel {
        Channel(
            id: .federated(id, provider: ContentSource.jellyfinProvider, instance: instanceURL),
            name: name,
            description: overview,
            subscriberCount: nil,
            videoCount: nil,
            thumbnailURL: thumbnailURL(instanceURL: instanceURL),
            bannerURL: nil
        )
    }
}

struct JellyfinUserData: Decodable, Sendable {
    let playbackPositionTicks: Int?
    let playedPercentage: Double?

    private enum CodingKeys: String, CodingKey {
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playedPercentage = "PlayedPercentage"
    }
}

struct JellyfinMediaSource: Decodable, Sendable {
    let id: String
    let container: String?
    let size: Int64?
    let mediaStreams: [JellyfinMediaStream]?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case container = "Container"
        case size = "Size"
        case mediaStreams = "MediaStreams"
    }
}

struct JellyfinMediaStream: Decodable, Sendable {
    let type: String?
    let codec: String?

    private enum CodingKeys: String, CodingKey {
        case type = "Type"
        case codec = "Codec"
    }
}
