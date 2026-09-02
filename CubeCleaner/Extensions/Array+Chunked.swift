// Array+Chunked.swift — 数组分块扩展

import Foundation

/// 将数组分割成指定大小的小批次，用于批量处理与内存优化。
extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
