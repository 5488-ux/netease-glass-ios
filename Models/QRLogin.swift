import Foundation

enum QRLoginStatus: String {
    case waiting = "等待扫码"
    case scanned = "等待确认"
    case success = "登录成功"
    case expired = "二维码过期"
    case failed = "登录失败"
}

struct QRLoginSession {
    let key: String
    let loginURL: URL
    let expiresAt: Date
}
