import Foundation
import XCTest

/// 测试夹具：独立临时路径；调用方负责 defer 清理。
/// 注意保持与 T/ 平级（不建子目录）：部分用例在 Store 创建目录前就打开原生 SQLite 连接。
func tempDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

func tempStoreURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
}
