import Foundation
import NotoCore

// NotoSync 两个远端调用（Supabase Auth、RPC 上传）共用的 POST 形态：
// 同样的超时、apikey 头与 JSON 内容类型；错误文案由调用方给出。

enum SyncHTTP {
    static func post(_ url: URL, apiKey: String, token: String? = nil, json body: Data) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 30
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return (data, status)
    }

    static func endpoint(_ base: URL, _ path: String) throws -> URL {
        let trimmed = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + "/" + path) else { throw NotoError("服务地址无效。") }
        return url
    }
}
