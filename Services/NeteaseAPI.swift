import CommonCrypto
import CryptoKit
import Foundation

struct DownloadPermission {
    let url: URL
    let totalBytes: Int64
    let bitrate: Int?
}

enum NeteaseAPIError: LocalizedError {
    case invalidURL
    case invalidResponse(String)
    case httpStatus(Int, String)
    case serverCode(Int, String)
    case message(String)
    case downloadUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "网易云请求地址无效"
        case let .invalidResponse(detail): return detail.isEmpty ? "网易云返回的数据无法解析" : detail
        case let .httpStatus(status, detail): return detail.isEmpty ? "网易云服务返回 HTTP \(status)" : detail
        case let .serverCode(code, detail): return detail.isEmpty ? "网易云接口返回错误（\(code)）" : detail
        case let .message(value), let .downloadUnavailable(value): return value
        }
    }

    /// 会话失效类错误（登录过期或需要重新登录），用于触发重新扫码登录。
    var isSessionExpired: Bool {
        switch self {
        case .serverCode(let code, _): return code == -1102 || code == 1102
        case .message(let value): return value.contains("登录状态已失效")
        default: return false
        }
    }

    static func userMessage(for error: Error) -> String {
        if let error = error as? NeteaseAPIError { return error.errorDescription ?? "网易云请求失败" }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet: return "网络未连接，请检查网络后重试"
            case .timedOut: return "网易云请求超时，请稍后重试"
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: return "无法连接网易云服务，请检查网络后重试"
            case .networkConnectionLost: return "网络连接中断，请返回应用后重试"
            case .cancelled: return "请求已取消"
            case .badServerResponse, .resourceUnavailable, .zeroByteResource: return "服务器拒绝了音频请求（可能为 403/版权限制），请尝试重新播放或更换歌曲"
            default:
                let raw = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
                return raw.isEmpty ? "网络请求失败（错误码 \(error.code.rawValue)），请稍后重试" : "网络请求失败（错误码 \(error.code.rawValue)）：\(raw)"
            }
        }
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.range(of: "[\\u{4E00}-\\u{9FFF}]", options: .regularExpression) != nil ? message : "请求失败，请稍后重试"
    }
}

final class NeteaseAPI {
    private let session: URLSession
    private let musicURL = URL(string: "https://music.163.com")!
    private let interfaceURL = URL(string: "https://interface3.music.163.com")!
    private let interfaceFallbackURL = URL(string: "https://interface.music.163.com")!
    private var cookie: String

    init(cookie: String = "") {
        self.cookie = cookie
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 25
        configuration.timeoutIntervalForResource = 90
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpAdditionalHeaders = ["User-Agent": Self.desktopUserAgent, "Referer": "https://music.163.com/", "Accept": "application/json, text/plain, */*"]
        session = URLSession(configuration: configuration)
    }

    var hasCookie: Bool { !cookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var currentCookie: String { cookie }
    func updateCookie(_ cookie: String) { self.cookie = cookie.trimmingCharacters(in: .whitespacesAndNewlines) }

    func searchSongs(_ keyword: String) async throws -> [Song] {
        try requireLogin()
        let json = try await cloudSearch(keyword, type: 1, limit: 30)
        return ((json["result"] as? [String: Any])?["songs"] as? [[String: Any]] ?? []).compactMap(parseSong)
    }

    func searchUsers(_ keyword: String) async throws -> [NeteaseUser] {
        try requireLogin()
        let json = try await cloudSearch(keyword, type: 1002, limit: 30)
        return ((json["result"] as? [String: Any])?["userprofiles"] as? [[String: Any]] ?? []).compactMap(parseUser)
    }

    func playlist(id: Int) async throws -> Playlist {
        try requireLogin()
        let json = try await weAPI(path: "/weapi/v3/playlist/detail", payload: ["id": id, "n": 0, "csrf_token": csrfToken])
        guard let payload = json["playlist"] as? [String: Any], var playlist = parsePlaylist(payload) else {
            throw NeteaseAPIError.message("歌单不存在，或当前账号没有访问权限")
        }
        let ids = (payload["trackIds"] as? [[String: Any]] ?? []).compactMap { int($0["id"]) }
        playlist.songs = try await fetchSongs(ids: ids)
        return playlist
    }

    func userPlaylists(userID: Int) async throws -> [Playlist] {
        try requireLogin()
        let json = try await weAPI(path: "/weapi/user/playlist", payload: ["uid": userID, "limit": 100, "offset": 0, "includeVideo": true, "csrf_token": csrfToken])
        return (json["playlist"] as? [[String: Any]] ?? []).compactMap(parsePlaylist)
    }

    func loadUser(_ user: NeteaseUser) async throws -> NeteaseUser {
        var result = user
        result.playlists = try await userPlaylists(userID: user.id)
        return result
    }

    func account() async throws -> NeteaseAccount {
        try requireLogin()
        let json = try await weAPI(path: "/weapi/nuser/account/get", payload: ["csrf_token": csrfToken])
        guard let profile = json["profile"] as? [String: Any], let userID = int(profile["userId"]), let nickname = profile["nickname"] as? String else {
            throw NeteaseAPIError.message("登录状态已失效，请重新扫码登录")
        }
        let user = NeteaseUser(id: userID, nickname: nickname, signature: profile["signature"] as? String ?? "暂无简介", avatarURL: secureURL(profile["avatarUrl"] as? String ?? ""), level: int(profile["level"]), vipType: int(profile["vipType"]), playlists: try await userPlaylists(userID: userID))
        return NeteaseAccount(user: user, cookie: cookie)
    }

    func createQRLogin() async throws -> QRLoginSession {
        var components = URLComponents(url: URL(string: "https://interface.music.163.com/api/login/qrcode/unikey")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "type", value: "3"), URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
        guard let url = components.url else { throw NeteaseAPIError.invalidURL }
        let json = try await requestJSON(url: url, method: "GET", body: nil, contentType: nil, context: "生成登录二维码")
        guard let key = json["unikey"] as? String, let loginURL = URL(string: "https://music.163.com/login?codekey=\(key.formURLEncoded)") else {
            throw NeteaseAPIError.message("二维码生成失败，请刷新后重试")
        }
        return QRLoginSession(key: key, loginURL: loginURL, expiresAt: Date().addingTimeInterval(300))
    }

    func checkQRLogin(_ session: QRLoginSession) async throws -> QRLoginStatus {
        guard Date() < session.expiresAt else { return .expired }
        var components = URLComponents(url: URL(string: "https://interface.music.163.com/api/login/qrcode/client/login")!, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "timestamp", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
        guard let url = components.url else { throw NeteaseAPIError.invalidURL }
        let body = "key=\(session.key.formURLEncoded)&type=3".data(using: .utf8)
        let (json, response) = try await requestJSONWithResponse(url: url, method: "POST", body: body, contentType: "application/x-www-form-urlencoded", context: "查询扫码状态", toleratedCodes: [800, 801, 802, 803])
        guard let code = int(json["code"]) else { throw NeteaseAPIError.invalidResponse("二维码登录状态无法识别") }
        switch code {
        case 801: return .waiting
        case 802: return .scanned
        case 800: return .expired
        case 803:
            let merged = Self.mergeCookieHeaders(Self.cookieHeader(from: response), json["cookie"] as? String ?? "")
            guard !merged.isEmpty else { throw NeteaseAPIError.message("扫码已确认，但网易云没有返回登录凭据，请刷新二维码重试") }
            cookie = merged
            return .success
        default: throw NeteaseAPIError.serverCode(code, serverMessage(from: json, fallback: "二维码登录被网易云拒绝（\(code)）"))
        }
    }

    func resolveDownload(for song: Song) async throws -> DownloadPermission {
        try requireLogin()
        let requestID = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let header = "{\"os\":\"pc\",\"appver\":\"\",\"osver\":\"\",\"deviceId\":\"pyncm!\",\"requestId\":\"\(requestID)\"}"
        let context = "接口 /eapi/song/enhance/player/url/v1（播放歌曲「\(song.name)」ID \(song.id)）"
        let json = try await eAPI(path: "/eapi/song/enhance/player/url/v1", payload: ["ids": [song.id], "level": "standard", "encodeType": "mp3", "header": header], context: context)
        guard let item = (json["data"] as? [[String: Any]])?.first else { throw NeteaseAPIError.downloadUnavailable("播放歌曲「\(song.name)」(ID \(song.id)) 失败：网易云没有返回播放权限信息") }
        let code = int(item["code"]) ?? -1
        if code == 200, let value = item["url"] as? String, !value.isEmpty, let url = secureURL(value) {
            return DownloadPermission(url: url, totalBytes: int64(item["size"]) ?? 0, bitrate: int(item["br"]))
        }
        let itemText = [item["message"] as? String, item["msg"] as? String, (item["freeTrialPrivilege"] as? [String: Any])?["cannotListenReason"] as? String]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
        let base = "播放歌曲「\(song.name)」(ID \(song.id)) 失败：网易云返回错误码 \(code)"
        let detail = base + (itemText.isEmpty ? "" : "（服务器消息：\(itemText)）") + "；登录状态：\(cookieStatusDescription)"
        if code == -1102 || code == 1102 {
            throw NeteaseAPIError.message(detail + "；该错误通常表示登录状态已失效，可到「设置」中重新扫码登录后重试")
        }
        let fee = int(item["fee"]) ?? song.fee
        if fee == 1 || fee == 4 || fee == 8 || code == -110 { throw NeteaseAPIError.downloadUnavailable(detail + "；该歌曲需要 VIP 或当前账号没有播放/下载权限") }
        throw NeteaseAPIError.downloadUnavailable(detail + "；可能受版权、地区或账号权限限制")
    }

    func imageData(url: URL?) async -> Data? {
        guard let url else { return nil }
        do {
            var request = URLRequest(url: url)
            request.setValue(Self.desktopUserAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
            return data
        } catch { return nil }
    }

    private func cloudSearch(_ keyword: String, type: Int, limit: Int) async throws -> [String: Any] {
        let payload: [String: Any] = ["method": "POST", "url": "https://music.163.com/api/cloudsearch/pc", "params": ["s": keyword, "type": type, "offset": 0, "limit": limit]]
        let eparams = try NeteaseCipher.encryptLinux(payload)
        return try await requestJSON(url: musicURL.appending(path: "/api/linux/forward"), method: "POST", body: "eparams=\(eparams.formURLEncoded)".data(using: .utf8), contentType: "application/x-www-form-urlencoded", context: "搜索接口 /api/linux/forward")
    }

    private func weAPI(path: String, payload: [String: Any], context: String? = nil) async throws -> [String: Any] {
        let form = try NeteaseCipher.encryptWeAPI(payload)
        return try await requestJSON(url: musicURL.appending(path: path), method: "POST", body: form.data(using: .utf8), contentType: "application/x-www-form-urlencoded", context: context ?? "接口 \(path)")
    }

    private func eAPI(path: String, payload: [String: Any], context: String? = nil) async throws -> [String: Any] {
        let form = try NeteaseCipher.encryptEAPI(path: path, payload: payload)
        let baseContext = context ?? "接口 \(path)"
        do {
            return try await requestJSON(url: interfaceURL.appending(path: path), method: "POST", body: form.data(using: .utf8), contentType: "application/x-www-form-urlencoded", context: baseContext)
        } catch let error as URLError where error.code != .cancelled {
            // interface3.music.163.com 在某些网络环境下连接异常，回退到 interface.music.163.com 重试一次
            return try await requestJSON(url: interfaceFallbackURL.appending(path: path), method: "POST", body: form.data(using: .utf8), contentType: "application/x-www-form-urlencoded", context: baseContext + "（已切换备用服务器 interface.music.163.com）")
        } catch {
            // 服务器拒绝（-1102 等）或请求已取消时不自动重试，避免掩盖真实原因
            throw error
        }
    }

    private func fetchSongs(ids: [Int]) async throws -> [Song] {
        var songs: [Song] = []
        for start in stride(from: 0, to: ids.count, by: 500) {
            let part = Array(ids[start..<min(start + 500, ids.count)])
            let c = try jsonString(part.map { ["id": $0] })
            let list = try jsonString(part)
            let json = try await weAPI(path: "/weapi/v3/song/detail", payload: ["c": c, "ids": list])
            songs += (json["songs"] as? [[String: Any]] ?? []).compactMap(parseSong)
        }
        return songs
    }

    private func requireLogin() throws { if !hasCookie { throw NeteaseAPIError.message("请先登录网易云音乐") } }
    private var csrfToken: String { cookie.split(separator: ";").compactMap { part in let p = part.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "=", maxSplits: 1); return p.count == 2 && p[0] == "__csrf" ? String(p[1]) : nil }.first ?? "" }

    private func requestJSON(url: URL, method: String, body: Data?, contentType: String?, context: String = "") async throws -> [String: Any] {
        let result = try await requestJSONWithResponse(url: url, method: method, body: body, contentType: contentType, context: context)
        return result.0
    }

    /// 当前登录凭证状态的简要描述，用于错误诊断。
    private var cookieStatusDescription: String {
        guard hasCookie else { return "未登录（无已保存凭证）" }
        let names = cookie.split(separator: ";").compactMap { part in part.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "=", maxSplits: 1).first.map(String.init) }
        if names.contains("MUSIC_U") { return "已保存登录凭证（包含 MUSIC_U，共 \(names.count) 个字段）" }
        return "已保存登录凭证（⚠️ 不含 MUSIC_U，仅字段：\(names.joined(separator: "、"))）"
    }

    /// 拼装带上下文的详细错误文本（包含服务器原始返回，便于定位真实原因）。
    private func rejectedMessage(code: Int, serverText: String, context: String, json: [String: Any]) -> String {
        var parts: [String] = ["网易云接口返回错误（\(code)）"]
        if !context.isEmpty { parts.append(context) }
        if !serverText.isEmpty { parts.append("服务器消息：\(serverText)") }
        parts.append("登录状态：\(cookieStatusDescription)")
        if let data = try? JSONSerialization.data(withJSONObject: json), let text = String(data: data, encoding: .utf8), !text.isEmpty {
            let snippet = text.count > 240 ? String(text.prefix(240)) + "…" : text
            parts.append("服务器返回：\(snippet)")
        }
        return parts.joined(separator: "；")
    }

    private func requestJSONWithResponse(url: URL, method: String, body: Data?, contentType: String?, context: String = "", toleratedCodes: Set<Int> = []) async throws -> ([String: Any], HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(Self.desktopUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if hasCookie { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NeteaseAPIError.invalidResponse("网易云没有返回有效响应\(context.isEmpty ? "" : "（\(context)）")") }
        let json = try decodeJSON(data)
        guard (200..<300).contains(http.statusCode) else {
            let serverText = serverMessage(from: json, fallback: "")
            throw NeteaseAPIError.httpStatus(http.statusCode, "HTTP \(http.statusCode)\(context.isEmpty ? "" : "（\(context)）")\(serverText.isEmpty ? "" : "：\(serverText)")")
        }
        if let code = int(json["code"]), code != 200, !toleratedCodes.contains(code) {
            let detail = rejectedMessage(code: code, serverText: serverMessage(from: json, fallback: ""), context: context, json: json)
            if code == -1102 || code == 1102 {
                // 附上服务器原文，避免掩盖真实原因；该码通常表示登录状态已失效
                throw NeteaseAPIError.serverCode(code, detail + "；该错误通常表示登录状态已失效，可到「设置」中重新扫码登录后重试")
            }
            throw NeteaseAPIError.serverCode(code, detail)
        }
        return (json, http)
    }

    private func decodeJSON(_ data: Data) throws -> [String: Any] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let text = String(data: data.prefix(120), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw NeteaseAPIError.invalidResponse(text.isEmpty ? "网易云返回的数据无法解析" : "网易云返回了非 JSON 数据：\(text)")
        }
        return json
    }

    private func serverMessage(from json: [String: Any], fallback: String) -> String {
        let messages = ["message", "msg", "reason"].compactMap { (json[$0] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if let chinese = messages.first(where: { $0.range(of: "[\\u{4E00}-\\u{9FFF}]", options: .regularExpression) != nil }) { return chinese }
        if let first = messages.first { return first }
        return fallback
    }
    private func jsonString(_ value: Any) throws -> String { guard let result = String(data: try JSONSerialization.data(withJSONObject: value), encoding: .utf8) else { throw NeteaseAPIError.message("请求参数编码失败") }; return result }
    private func int(_ value: Any?) -> Int? { if let v = value as? Int { return v }; if let v = value as? Int64 { return Int(v) }; if let v = value as? NSNumber { return v.intValue }; if let v = value as? String { return Int(v) }; return nil }
    private func int64(_ value: Any?) -> Int64? { if let v = value as? Int64 { return v }; if let v = value as? Int { return Int64(v) }; if let v = value as? NSNumber { return v.int64Value }; if let v = value as? String { return Int64(v) }; return nil }

    private func parseSong(_ raw: [String: Any]) -> Song? {
        guard let id = int(raw["id"]), let name = raw["name"] as? String else { return nil }
        let artists = (raw["artists"] as? [[String: Any]] ?? raw["ar"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }.joined(separator: "、")
        let album = raw["album"] as? [String: Any] ?? raw["al"] as? [String: Any] ?? [:]
        let privilege = raw["privilege"] as? [String: Any] ?? [:]
        let fee = int(raw["fee"] ?? privilege["fee"]) ?? 0
        return Song(id: id, name: name, artist: artists, album: album["name"] as? String ?? "未知专辑", duration: Double(int(raw["duration"] ?? raw["dt"]) ?? 0) / 1000, coverURL: secureURL(album["picUrl"] as? String ?? raw["picUrl"] as? String ?? ""), fee: fee, isVIP: fee == 1 || fee == 4 || fee == 8, size: nil, bitrate: nil)
    }

    private func parsePlaylist(_ raw: [String: Any]) -> Playlist? {
        guard let id = int(raw["id"]), let name = raw["name"] as? String else { return nil }
        let creator = raw["creator"] as? [String: Any]
        return Playlist(id: id, name: name, creatorName: creator?["nickname"] as? String ?? "未知创建者", description: raw["description"] as? String ?? "", trackCount: int(raw["trackCount"]) ?? 0, coverURL: secureURL(raw["coverImgUrl"] as? String ?? raw["picUrl"] as? String ?? ""))
    }

    private func parseUser(_ raw: [String: Any]) -> NeteaseUser? {
        guard let id = int(raw["userId"] ?? raw["id"]), let nickname = raw["nickname"] as? String else { return nil }
        return NeteaseUser(id: id, nickname: nickname, signature: raw["signature"] as? String ?? "暂无简介", avatarURL: secureURL(raw["avatarUrl"] as? String ?? ""), level: int(raw["level"]), vipType: int(raw["vipType"]))
    }

    private func secureURL(_ value: String) -> URL? { guard !value.isEmpty else { return nil }; var c = URLComponents(string: value); if c?.scheme?.lowercased() == "http" { c?.scheme = "https" }; return c?.url }
    private static func cookieHeader(from response: HTTPURLResponse) -> String {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { r, item in if let key = item.key as? String, let value = item.value as? String { r[key] = value } }
        return HTTPCookie.cookies(withResponseHeaderFields: headers, for: response.url ?? URL(string: "https://music.163.com")!).map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
    private static func mergeCookieHeaders(_ headers: String...) -> String {
        let ignored: Set<String> = ["path", "domain", "expires", "max-age", "secure", "httponly", "samesite", "priority"]
        var values: [String: String] = [:]
        for header in headers { for part in header.split(separator: ";") { let item = part.trimmingCharacters(in: .whitespacesAndNewlines); guard let index = item.firstIndex(of: "=") else { continue }; let name = item[..<index].trimmingCharacters(in: .whitespacesAndNewlines); let value = item[item.index(after: index)...].trimmingCharacters(in: .whitespacesAndNewlines); if !name.isEmpty && !value.isEmpty && !ignored.contains(name.lowercased()) { values[String(name)] = String(value) } } }
        return values.keys.sorted().compactMap { key in
            values[key].map { value in "\(key)=\(value)" }
        }.joined(separator: "; ")
    }
    private static let desktopUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120 Safari/537.36 NeteaseMusicDesktop/3.0.18.203152"
}

private enum NeteaseCipher {
    private static let linuxKey = "rFgB&h#%2?^eDg:Q"
    private static let weAPIKey = "0CoJUm6Qyw8W8jud"
    private static let weAPIIV = "0102030405060708"
    private static let fixedSecret = "NeteaseGlassKey!"
    private static let encryptedSecret = "dfc6e103ef069965a7ab599d1c82db759459febb99f2e90d6284964ee6408e77942e9ccf3978dd80be05727b13535feca688259ea807835066cba93000d3cafb91d0c6c0fe3fc7b03720b00f1c655dc11b0efa6f2cedf2b8431b0d40ed1a78ee0ee0874de1883573c17410f1eccbc14ddf0c9e28961c5c96833336c2abb01fa1"
    private static let eAPIKey = "e82ckenh8dichen8"

    static func encryptLinux(_ payload: [String: Any]) throws -> String { try aes(JSONSerialization.data(withJSONObject: payload), key: linuxKey, iv: nil, ecb: true).hexString.uppercased() }
    static func encryptWeAPI(_ payload: [String: Any]) throws -> String {
        let first = try aes(JSONSerialization.data(withJSONObject: payload), key: weAPIKey, iv: weAPIIV, ecb: false).base64EncodedString()
        let second = try aes(Data(first.utf8), key: fixedSecret, iv: weAPIIV, ecb: false).base64EncodedString()
        return "params=\(second.formURLEncoded)&encSecKey=\(encryptedSecret)"
    }
    static func encryptEAPI(path: String, payload: [String: Any]) throws -> String {
        let payloadData = try JSONSerialization.data(withJSONObject: payload)
        guard let payloadText = String(data: payloadData, encoding: .utf8) else { throw NeteaseAPIError.message("下载参数编码失败") }
        let apiPath = path.replacingOccurrences(of: "/eapi/", with: "/api/")
        let source = "nobody\(apiPath)use\(payloadText)md5forencrypt"
        let digest = Insecure.MD5.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        let encrypted = try aes(Data("\(apiPath)-36cd479b6b5-\(payloadText)-36cd479b6b5-\(digest)".utf8), key: eAPIKey, iv: nil, ecb: true).hexString
        return "params=\(encrypted)"
    }
    private static func aes(_ input: Data, key: String, iv: String?, ecb: Bool) throws -> Data {
        let keyData = Data(key.utf8), ivData = iv.map { Data($0.utf8) }
        var output = Data(count: input.count + kCCBlockSizeAES128), count = 0
        let options = CCOptions(kCCOptionPKCS7Padding | (ecb ? kCCOptionECBMode : 0))
        let status = output.withUnsafeMutableBytes { out in input.withUnsafeBytes { input in keyData.withUnsafeBytes { key in if let ivData { return ivData.withUnsafeBytes { iv in CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), options, key.baseAddress, keyData.count, iv.baseAddress, input.baseAddress, input.count, out.baseAddress, out.count, &count) } }; return CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), options, key.baseAddress, keyData.count, nil, input.baseAddress, input.count, out.baseAddress, out.count, &count) } } }
        guard status == kCCSuccess else { throw NeteaseAPIError.message("本地请求加密失败（\(status)）") }
        output.removeSubrange(count..<output.count)
        return output
    }
}

private extension Data { var hexString: String { map { String(format: "%02x", $0) }.joined() } }
private extension String { var formURLEncoded: String { addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._*"))) ?? self } }
