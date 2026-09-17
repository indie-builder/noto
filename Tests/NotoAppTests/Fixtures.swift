import Foundation
import XCTest
import NotoCore
@testable import NotoApp

// 测试夹具：一次搭建「内存库 + 完成首轮加载」的 AppModel。

/// 独立临时文件路径；调用方负责 defer 清理。
func tempStoreURL(extension ext: String = ".sqlite") -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ext)
}

/// 内存库模型，已等待首轮 reload 完成。
@MainActor
func makeModel(_ store: Store? = nil) async throws -> AppModel {
    let model = AppModel(store: try store ?? Store(url: nil))
    await model.waitForReload()
    return model
}
