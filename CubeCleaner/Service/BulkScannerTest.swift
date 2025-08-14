import Foundation

/**
 * 批量文件扫描器的测试和性能验证
 * 
 * 此文件包含了对新的getattrlistbulk实现的测试用例
 * 可以用来验证性能提升和正确性
 */
class BulkScannerTest {
    
    /**
     * 性能对比测试：比较批量扫描和传统扫描的性能差异
     * @param testDirectory: 测试目录路径
     */
    static func performanceComparison(testDirectory: String) {
        print("开始性能对比测试...")
        print("测试目录: \(testDirectory)")
        
        // 测试批量扫描性能
        let bulkStartTime = CFAbsoluteTimeGetCurrent()
        do {
            let bulkResults = try BulkFileScanner.scanDirectory(at: testDirectory)
            let bulkEndTime = CFAbsoluteTimeGetCurrent()
            let bulkDuration = bulkEndTime - bulkStartTime
            
            print("批量扫描结果:")
            print("- 文件数量: \(bulkResults.count)")
            print("- 扫描耗时: \(String(format: "%.3f", bulkDuration))秒")
            print("- 平均每文件: \(String(format: "%.3f", bulkDuration * 1000 / Double(bulkResults.count)))毫秒")
            
        } catch {
            print("批量扫描失败: \(error)")
        }
        
        // 测试传统扫描性能（使用FileManager）
        let traditionalStartTime = CFAbsoluteTimeGetCurrent()
        do {
            let traditionalResults = try scanDirectoryTraditional(at: testDirectory)
            let traditionalEndTime = CFAbsoluteTimeGetCurrent()
            let traditionalDuration = traditionalEndTime - traditionalStartTime
            
            print("\n传统扫描结果:")
            print("- 文件数量: \(traditionalResults.count)")
            print("- 扫描耗时: \(String(format: "%.3f", traditionalDuration))秒")
            print("- 平均每文件: \(String(format: "%.3f", traditionalDuration * 1000 / Double(traditionalResults.count)))毫秒")
            
            // 计算性能提升
            if traditionalDuration > 0 {
                let improvement = traditionalDuration / bulkStartTime
                print("\n性能提升: \(String(format: "%.1f", improvement))倍")
            }
            
        } catch {
            print("传统扫描失败: \(error)")
        }
    }
    
    /**
     * 传统文件扫描方法（用于性能对比）
     */
    private static func scanDirectoryTraditional(at path: String) throws -> [URL] {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: path)
        
        return try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [
                .nameKey, .fileSizeKey, .isDirectoryKey,
                .creationDateKey, .contentModificationDateKey
            ],
            options: [.skipsHiddenFiles]
        )
    }
    
    /**
     * 内存使用测试：监控扫描过程中的内存使用情况
     */
    static func memoryUsageTest(testDirectory: String) {
        print("开始内存使用测试...")
        
        let startMemory = getMemoryUsage()
        print("初始内存使用: \(formatBytes(startMemory))")
        
        do {
            let results = try BulkFileScanner.scanDirectory(at: testDirectory)
            let peakMemory = getMemoryUsage()
            
            print("扫描完成后内存使用: \(formatBytes(peakMemory))")
            print("内存增长: \(formatBytes(peakMemory - startMemory))")
            print("平均每文件内存开销: \(formatBytes((peakMemory - startMemory) / Int64(results.count)))")
            
        } catch {
            print("内存测试失败: \(error)")
        }
    }
    
    /**
     * 获取当前进程的内存使用量
     */
    private static func getMemoryUsage() -> Int64 {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            return Int64(taskInfo.phys_footprint)
        }
        return 0
    }
    
    /**
     * 格式化字节数为可读字符串
     */
    private static func formatBytes(_ bytes: Int64) -> String {
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .memory)
    }
}

// MARK: - 使用示例
/*
// 在需要测试的地方调用：
BulkScannerTest.performanceComparison(testDirectory: "/Users/用户名/Documents")
BulkScannerTest.memoryUsageTest(testDirectory: "/Users/用户名/Documents")
*/
