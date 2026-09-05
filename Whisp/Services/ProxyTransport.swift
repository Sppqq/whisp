import Foundation
import CFNetwork

final class ProxyAuthenticationDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.isProxy(), !username.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(
            .useCredential,
            URLCredential(user: username, password: password, persistence: .forSession)
        )
    }
}

enum ProxyTransport {
    static func authenticationDelegate(proxy: ProxyConfiguration) -> ProxyAuthenticationDelegate? {
        guard proxy.isEnabled, !proxy.username.isEmpty else { return nil }
        return ProxyAuthenticationDelegate(username: proxy.username, password: proxy.password)
    }

    static func sessionConfiguration(proxy: ProxyConfiguration) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        guard proxy.isEnabled, !proxy.host.isEmpty, proxy.port > 0 else { return configuration }

        var dictionary: [AnyHashable: Any] = [:]
        switch proxy.kind {
        case .socks5:
            dictionary[kCFNetworkProxiesSOCKSEnable] = 1
            dictionary[kCFNetworkProxiesSOCKSProxy] = proxy.host
            dictionary[kCFNetworkProxiesSOCKSPort] = proxy.port
            if !proxy.username.isEmpty {
                dictionary[kCFProxyUsernameKey] = proxy.username
                dictionary[kCFProxyPasswordKey] = proxy.password
            }
        case .http:
            dictionary[kCFNetworkProxiesHTTPEnable] = 1
            dictionary[kCFNetworkProxiesHTTPProxy] = proxy.host
            dictionary[kCFNetworkProxiesHTTPPort] = proxy.port
            dictionary[kCFNetworkProxiesHTTPSEnable] = 1
            dictionary[kCFNetworkProxiesHTTPSProxy] = proxy.host
            dictionary[kCFNetworkProxiesHTTPSPort] = proxy.port
            if !proxy.username.isEmpty {
                dictionary[kCFProxyUsernameKey] = proxy.username
                dictionary[kCFProxyPasswordKey] = proxy.password
            }
        }
        configuration.connectionProxyDictionary = dictionary
        return configuration
    }
}
