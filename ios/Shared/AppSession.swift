import Foundation

/// 全 App 统一的 URLSession：可选手动代理。
///
/// 背景：模拟器/部分网络环境下系统代理对 App 不生效，直连 api.github.com 会被
/// 断连（TLS error / 挂起）。设置里填了代理（如 127.0.0.1:7897）就走代理，
/// 留空保持系统默认。改代理值会换新会话，立即生效，不用重启 App。
extension URLSession {
    private static var cachedProxySession: (key: String, session: URLSession)?

    static var app: URLSession {
        let key = UserDefaults.standard.string(forKey: "network.proxy") ?? ""
            .trimmingCharacters(in: .whitespaces)
        if let cached = cachedProxySession, cached.key == key {
            return cached.session
        }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        if !key.isEmpty, let colon = key.firstIndex(of: ":"),
           let port = Int(key[key.index(after: colon)...]) {
            let host = String(key[..<colon])
            // iOS 上没有独立的 HTTPS 代理键，HTTP 代理键同时接管 https 的 CONNECT 隧道。
            config.connectionProxyDictionary = [
                kCFNetworkProxiesHTTPEnable as String: true,
                kCFNetworkProxiesHTTPProxy as String: host,
                kCFNetworkProxiesHTTPPort as String: port,
            ]
        }
        let session = URLSession(configuration: config)
        cachedProxySession = (key, session)
        return session
    }
}
