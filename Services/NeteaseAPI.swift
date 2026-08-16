import Foundation

struct DownloadPermission {
    let url: URL
    let totalBytes: Int64
    let bitrate: Int?
}

enum NeteaseAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case message(String)
    case downloadUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "网易云请求地址无效"
        case .invalidResponse: return "网易云返回的数据无法解析"
        case let .message(value): return value
        case let .downloadUnavailable(value): return value
        }
    }

    static func userMessage(for error: Error) -> String {
        if let apiError = error as? NeteaseAPIError {
            return apiError.errorDescription ?? "网易云请求失败"
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "网络未连接，请检查网络后重试"
            case .timedOut:
                return "请求超时，请稍后重试"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "无法连接网易云服务，请检查网络后重试"
            case .networkConnectionLost:
                return "网络连接中断，请返回应用后重试"
            default:
                return "网络请求失败，请稍后重试"
            }
        }

        let message = error.localizedDescription
        if message.range(of: "[\\u{4E00}-\\u{9FFF}]", options: .regularExpression) != nil {
            return message
        }
        return "请求失败，请检查网络后重试"
    }
}

final class NeteaseAPI {
    private let session: URLSession
    private let baseURL = URL(string: "https://music.163.com")!
    private let downloadBaseURL = URL(string: "https://interface3.music.163.com")!
    private var cookie: String

    init(cookie: String = "") {
        self.cookie = cookie
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 60
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            "Referer": "https://music.163.com/"
        ]
        session = URLSession(configuration: configuration)
    }

    var hasCookie: Bool { !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var currentCookie: String { cookie }

    func updateCookie(_ cookie: String) { self.cookie = cookie }

    func searchSongs(_ keyword: String) async throws -> [Song] {
        try requireLogin()
        let json = try await get(path: "/api/search/get/web", query: [
            URLQueryItem(name: "s", value: keyword),
            URLQueryItem(name: "type", value: "1"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "30")
        ])
        guard let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]] else { return [] }
        return songs.compactMap(parseSong)
    }

    func searchUsers(_ keyword: String) async throws -> [NeteaseUser] {
        try requireLogin()
        let json = try await get(path: "/api/search/get/web", query: [
            URLQueryItem(name: "s", value: keyword),
            URLQueryItem(name: "type", value: "1002"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "limit", value: "30")
        ])
        guard let result = json["result"] as? [String: Any],
              let users = result["userprofiles"] as? [[String: Any]] else { return [] }
        return users.compactMap(parseUser)
    }

    func playlist(id: Int) async throws -> Playlist {
        try requireLogin()
        let json = try await get(path: "/api/playlist/detail", query: [URLQueryItem(name: "id", value: String(id)), URLQueryItem(name: "s", value: "0")])
        guard let payload = json["playlist"] as? [String: Any], let playlist = parsePlaylist(payload) else {
            throw NeteaseAPIError.message("歌单不存在或网易云拒绝了请求")
        }

        var songs = (payload["tracks"] as? [[String: Any]] ?? []).compactMap(parseSong)
        let trackIDs = (payload["trackIds"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? Int }
        if songs.count < trackIDs.count {
            songs = try await fetchSongs(ids: trackIDs)
        }
        var result = playlist
        result.songs = songs
        return result
    }

    func userPlaylists(userID: Int) async throws -> [Playlist] {
        try requireLogin()
        let json = try await get(path: "/api/user/playlist", query: [
            URLQueryItem(name: "uid", value: String(userID)),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "includeVideo", value: "true")
        ])
        let items = json["playlist"] as? [[String: Any]] ?? []
        return items.compactMap(parsePlaylist)
    }

    func loadUser(_ user: NeteaseUser) async throws -> NeteaseUser {
        var result = user
        result.playlists = try await userPlaylists(userID: user.id)
        return result
    }

    func account() async throws -> NeteaseAccount {
        guard hasCookie else { throw NeteaseAPIError.message("请先登录网易云音乐") }
        let json = try await get(path: "/api/nuser/account/get", query: [])
        guard let profile = json["profile"] as? [String: Any],
              let userID = int(profile["userId"]),
              let nickname = profile["nickname"] as? String else {
            throw NeteaseAPIError.message("登录状态已失效，请重新扫码登录")
        }
        let user = NeteaseUser(
            id: userID,
            nickname: nickname,
            signature: profile["signature"] as? String ?? "",
            avatarURL: URL(string: profile["avatarUrl"] as? String ?? ""),
            level: int(profile["level"]),
            vipType: int(profile["vipType"]),
            playlists: try await userPlaylists(userID: userID)
        )
        return NeteaseAccount(user: user, cookie: cookie)
    }

    func createQRLogin() async throws -> QRLoginSession {
        var components = URLComponents(url: URL(string: "https://interface.music.163.com/api/login/qrcode/unikey")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "type", value: "3"),
            URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000)))
        ]
        guard let requestURL = components.url else { throw NeteaseAPIError.invalidURL }
        let json = try await getRaw(url: requestURL, method: "GET", body: nil)
        guard let code = int(json["code"]), code == 200, let key = json["unikey"] as? String,
              let loginURL = URL(string: "https://music.163.com/login?codekey=\(key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key)") else {
            throw NeteaseAPIError.message("二维码生成失败")
        }
        return QRLoginSession(key: key, loginURL: loginURL, expiresAt: Date().addingTimeInterval(300))
    }

    func checkQRLogin(_ session: QRLoginSession) async throws -> QRLoginStatus {
        guard Date() < session.expiresAt else { return .expired }
        var components = URLComponents(url: URL(string: "https://interface.music.163.com/api/login/qrcode/client/login")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpBody = "key=\(session.key.urlEncoded)&type=3".data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36 NeteaseMusicDesktop/3.0.18.203152", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let code = int(json["code"]) else {
            throw NeteaseAPIError.invalidResponse
        }

        switch code {
        case 801: return .waiting
        case 802: return .scanned
        case 800: return .expired
        case 803:
            let responseCookie = (json["cookie"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let setCookie = Self.cookieHeader(from: http)
            let merged = Self.mergeCookieHeaders(setCookie, responseCookie)
            if !merged.isEmpty { cookie = merged }
            return .success
        default: return .failed
        }
    }

    func resolveDownload(for song: Song) async throws -> DownloadPermission {
        try requireLogin()
        let id = "[\(song.id)]".urlEncoded
        let url = downloadBaseURL.appending(path: "/api/song/enhance/player/url/v1")
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        var requestComponents = components
        requestComponents.queryItems = [
            URLQueryItem(name: "ids", value: "[\(song.id)]"),
            URLQueryItem(name: "level", value: "standard"),
            URLQueryItem(name: "encodeType", value: "mp3")
        ]
        guard let requestURL = requestComponents.url else { throw NeteaseAPIError.invalidURL }
        let json = try await getRaw(url: requestURL, method: "GET", body: nil)
        guard let data = (json["data"] as? [[String: Any]])?.first else {
            throw NeteaseAPIError.downloadUnavailable("网易云没有返回这首歌曲的权限信息")
        }
        let code = int(data["code"]) ?? -1
        if code == 200, let urlString = data["url"] as? String, let audioURL = URL(string: urlString), !urlString.isEmpty {
            return DownloadPermission(url: audioURL, totalBytes: int64(data["size"]) ?? 0, bitrate: int(data["br"]))
        }

        let fee = int(data["fee"]) ?? song.fee
        let reason = (data["freeTrialPrivilege"] as? [String: Any])?["cannotListenReason"] as? String
        if fee == 1 || fee == 4 || fee == 8 || code == -110 {
            throw NeteaseAPIError.downloadUnavailable(reason ?? "你没有该歌曲的下载权限，或该歌曲需要 VIP")
        }
        throw NeteaseAPIError.downloadUnavailable(reason ?? "该歌曲当前不可下载，可能受版权或地区限制")
    }

    func imageData(url: URL?) async -> Data? {
        guard let url else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return data
        } catch {
            return nil
        }
    }

    private func fetchSongs(ids: [Int]) async throws -> [Song] {
        var result: [Song] = []
        for start in stride(from: 0, to: ids.count, by: 500) {
            let end = min(start + 500, ids.count)
            let idString = "[\(ids[start..<end].map(String.init).joined(separator: ","))]"
            let json = try await get(path: "/api/song/detail", query: [URLQueryItem(name: "ids", value: idString)])
            result.append(contentsOf: (json["songs"] as? [[String: Any]] ?? []).compactMap(parseSong))
        }
        return result
    }

    private func get(path: String, query: [URLQueryItem]) async throws -> [String: Any] {
        guard var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false) else { throw NeteaseAPIError.invalidURL }
        components.queryItems = query
        guard let url = components.url else { throw NeteaseAPIError.invalidURL }
        return try await getRaw(url: url, method: "GET", body: nil)
    }

    private func requireLogin() throws {
        guard hasCookie else { throw NeteaseAPIError.message("请先登录网易云音乐") }
    }

    private func getRaw(url: URL, method: String, body: Data?) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if hasCookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw NeteaseAPIError.invalidResponse }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw NeteaseAPIError.invalidResponse }
        return json
    }

    private func parseSong(_ raw: [String: Any]) -> Song? {
        guard let id = int(raw["id"]), let name = raw["name"] as? String else { return nil }
        let artists = (raw["artists"] as? [[String: Any]] ?? raw["ar"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let album = raw["album"] as? [String: Any] ?? raw["al"] as? [String: Any] ?? [:]
        let coverString = (album["picUrl"] as? String) ?? (raw["picUrl"] as? String) ?? ""
        let fee = int(raw["fee"]) ?? 0
        let vip = fee == 1 || fee == 4 || fee == 8
        return Song(id: id, name: name, artist: artists.joined(separator: "、"), album: album["name"] as? String ?? "未知专辑", duration: Double(int(raw["duration"] ?? raw["dt"]) ?? 0) / 1000, coverURL: secureURL(coverString), fee: fee, isVIP: vip, size: nil, bitrate: nil)
    }

    private func parsePlaylist(_ raw: [String: Any]) -> Playlist? {
        guard let id = int(raw["id"]), let name = raw["name"] as? String else { return nil }
        let creator = raw["creator"] as? [String: Any]
        let cover = raw["coverImgUrl"] as? String ?? raw["picUrl"] as? String ?? ""
        return Playlist(id: id, name: name, creatorName: creator?["nickname"] as? String ?? "未知创建者", description: raw["description"] as? String ?? "", trackCount: int(raw["trackCount"] ?? raw["trackNumberUpdateTime"]) ?? 0, coverURL: secureURL(cover))
    }

    private func parseUser(_ raw: [String: Any]) -> NeteaseUser? {
        guard let id = int(raw["userId"] ?? raw["id"]), let nickname = raw["nickname"] as? String else { return nil }
        return NeteaseUser(id: id, nickname: nickname, signature: raw["signature"] as? String ?? "暂无简介", avatarURL: secureURL(raw["avatarUrl"] as? String ?? ""), level: int(raw["level"]), vipType: int(raw["vipType"]))
    }

    private func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Int64 { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func int64(_ value: Any?) -> Int64? {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        return nil
    }

    private func secureURL(_ value: String) -> URL? {
        guard var components = URLComponents(string: value) else { return nil }
        if components.scheme?.lowercased() == "http" {
            components.scheme = "https"
        }
        return components.url
    }

    private static func cookieHeader(from response: HTTPURLResponse) -> String {
        let cookies = HTTPCookie.cookies(withResponseHeaderFields: response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String, let value = item.value as? String else { return }
            result[key] = value
        }, for: response.url ?? URL(string: "https://music.163.com")!)
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    private static func mergeCookieHeaders(_ headers: String...) -> String {
        let ignoredAttributes: Set<String> = [
            "path", "domain", "expires", "max-age", "secure", "httponly", "samesite", "priority"
        ]
        var values: [String: String] = [:]

        for header in headers {
            for part in header.split(separator: ";") {
                let item = part.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let separator = item.firstIndex(of: "=") else { continue }
                let name = item[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                let value = item[item.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, !value.isEmpty, !ignoredAttributes.contains(name.lowercased()) else { continue }
                values[String(name)] = String(value)
            }
        }

        return values.keys.sorted().compactMap { key in
            guard let value = values[key] else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: "; ")
    }
}

private extension String {
    var urlEncoded: String { addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? self }
}
