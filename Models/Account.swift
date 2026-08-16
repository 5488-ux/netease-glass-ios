import Foundation

struct NeteaseAccount: Codable, Hashable {
    var user: NeteaseUser
    var cookie: String
}
