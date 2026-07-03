// Array+Chunked.swift — 数组分块扩展

import Foundation

// MARK: Array+Chunked - 数组分块扩展
/// 为Array添加chunked方法，用于将大数组分割成小批次处理
/// 这样可以优化内存使用，避免一次性处理太多数据
///
/// 使用场景：
/// - 批量文件处理
/// - 内存优化
/// - 流式数据处理
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
