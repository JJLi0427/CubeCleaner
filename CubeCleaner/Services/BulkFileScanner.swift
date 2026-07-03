// BulkFileScanner.swift — 批量文件扫描器

import Darwin
import Foundation

// MARK: - 批量文件属性结构
/// 用于getattrlistbulk批量获取文件属性的结构体
/// 这个结构体包含了文件扫描需要的所有关键属性，优化内存使用
struct BulkFileAttributes {
    let name: String
    let size: Int64
    let isDirectory: Bool
    let creationDate: Date
    let modificationDate: Date
    let path: String
}

// MARK: - 批量文件扫描器
/// 使用getattrlistbulk API进行高效文件扫描的类
/// 相比传统的逐个文件扫描，批量API可以显著提升性能
///
/// 性能优势：
/// - 减少系统调用次数：一次调用获取多个文件属性
/// - 降低上下文切换开销：批量处理减少内核态/用户态切换
/// - 优化内存使用：使用固定大小缓冲区，避免内存碎片
/// - 提升缓存命中率：连续读取文件属性，提高磁盘缓存效率
class BulkFileScanner {

    // 批量处理的文件数量，平衡内存使用和性能
    private static let batchSize: Int = 512

    // 缓冲区大小：64KB，优化内存使用和IO性能
    private static let bufferSize: Int = 64 * 1024

    /**
     * 使用getattrlistbulk批量扫描目录内容
     * @param directoryPath: 要扫描的目录路径
     * @returns: 包含文件属性的数组
     * @throws: 文件系统访问错误
     */
    static func scanDirectory(at directoryPath: String) throws -> [BulkFileAttributes] {
        let dirFD = open(directoryPath, O_RDONLY)
        guard dirFD >= 0 else {
            throw POSIXError(.EACCES)
        }
        defer { close(dirFD) }

        // 设置要获取的属性列表
        var attrList = attrlist()
        attrList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)

        // 文件系统属性
        attrList.commonattr = UInt32(
            ATTR_CMN_NAME | ATTR_CMN_OBJTYPE | ATTR_CMN_CRTIME | ATTR_CMN_MODTIME)

        // 文件属性
        attrList.fileattr = UInt32(ATTR_FILE_DATALENGTH)

        var fileAttributes: [BulkFileAttributes] = []
        var buffer = [UInt8](repeating: 0, count: bufferSize)  // 使用预定义的缓冲区大小

        while true {
            // 调用getattrlistbulk获取批量文件属性
            let count = buffer.withUnsafeMutableBytes { bufferPtr in
                getattrlistbulk(dirFD, &attrList, bufferPtr.baseAddress, bufferPtr.count, 0)
            }

            if count == 0 {
                break  // 没有更多文件
            }

            if count < 0 {
                let error = errno
                if error == ENOENT || error == ENOTDIR {
                    break  // 目录不存在或不是目录，正常结束
                }
                throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EACCES)
            }

            // 解析缓冲区中的属性数据
            let parsedFiles = try parseAttributeBuffer(
                buffer, count: Int(count), basePath: directoryPath)
            fileAttributes.append(contentsOf: parsedFiles)

            // 如果返回的文件数少于期望，说明已经读完
            if count < batchSize {
                break
            }
        }

        return fileAttributes
    }

    /**
     * 解析getattrlistbulk返回的属性缓冲区
     * @param buffer: 包含属性数据的缓冲区
     * @param count: 返回的文件数量
     * @param basePath: 基础路径
     * @returns: 解析后的文件属性数组
     */
    private static func parseAttributeBuffer(_ buffer: [UInt8], count: Int, basePath: String) throws
        -> [BulkFileAttributes]
    {
        var fileAttributes: [BulkFileAttributes] = []
        var offset = 0

        for _ in 0..<count {
            guard offset < buffer.count else { break }

            // 读取当前条目的长度
            let entryLength = buffer.withUnsafeBytes { bytes in
                bytes.load(fromByteOffset: offset, as: UInt32.self)
            }

            guard offset + Int(entryLength) <= buffer.count else { break }

            let entryData = Array(buffer[offset..<offset + Int(entryLength)])

            do {
                let attributes = try parseFileAttributes(from: entryData, basePath: basePath)
                fileAttributes.append(attributes)
            } catch {
                // 跳过解析失败的条目，继续处理下一个
                print("跳过解析失败的文件条目: \(error)")
            }

            offset += Int(entryLength)
        }

        return fileAttributes
    }

    /**
     * 从单个文件的属性数据中解析文件信息
     * @param data: 文件属性数据
     * @param basePath: 基础路径
     * @returns: 解析后的文件属性
     */
    private static func parseFileAttributes(from data: [UInt8], basePath: String) throws
        -> BulkFileAttributes
    {
        var offset = 4  // 跳过长度字段

        // 读取文件名
        guard offset + 4 <= data.count else {
            throw FileSystemError.invalidPath
        }

        let nameInfo = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: attrreference.self)
        }
        offset += MemoryLayout<attrreference>.size

        let nameOffset = Int(nameInfo.attr_dataoffset)
        let nameLength = Int(nameInfo.attr_length)

        guard nameOffset + nameLength <= data.count else {
            throw FileSystemError.invalidPath
        }

        let nameData = Array(data[nameOffset..<nameOffset + nameLength])
        let fileName = String(cString: nameData)  // C字符串以null结尾

        // 读取文件类型
        guard offset + 4 <= data.count else {
            throw FileSystemError.invalidPath
        }

        let objType = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: UInt32.self)
        }
        offset += 4

        let isDirectory = (objType == VDIR.rawValue)

        // 读取创建时间
        guard offset + MemoryLayout<timespec>.size <= data.count else {
            throw FileSystemError.invalidPath
        }

        let creationTime = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: timespec.self)
        }
        offset += MemoryLayout<timespec>.size

        // 读取修改时间
        guard offset + MemoryLayout<timespec>.size <= data.count else {
            throw FileSystemError.invalidPath
        }

        let modificationTime = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: offset, as: timespec.self)
        }
        offset += MemoryLayout<timespec>.size

        // 读取文件大小（仅对普通文件有效）
        var fileSize: Int64 = 0
        if !isDirectory {
            guard offset + 8 <= data.count else {
                throw FileSystemError.invalidPath
            }

            fileSize = data.withUnsafeBytes { bytes in
                bytes.load(fromByteOffset: offset, as: Int64.self)
            }
        }

        // 构造完整路径
        let fullPath = (basePath as NSString).appendingPathComponent(fileName)

        // 转换时间戳为Date对象
        let creationDate = Date(
            timeIntervalSince1970: Double(creationTime.tv_sec) + Double(creationTime.tv_nsec)
                / 1_000_000_000)
        let modificationDate = Date(
            timeIntervalSince1970: Double(modificationTime.tv_sec) + Double(
                modificationTime.tv_nsec) / 1_000_000_000)

        return BulkFileAttributes(
            name: fileName,
            size: fileSize,
            isDirectory: isDirectory,
            creationDate: creationDate,
            modificationDate: modificationDate,
            path: fullPath
        )
    }
}
