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
    let isSymbolicLink: Bool
    let path: String
    /// 文件所在卷的 fsid（int32 对）。非 APFS 或解析失败时为 nil，调用方据此决定能否做卷边界判断。
    let fsid: (Int32, Int32)?
    /// 对象 id（APFS 上为 inode 号）。用于硬链接/firmlink 去重。不可靠或不存在时为 nil。
    let fileID: UInt64?
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

    /// 请求的 common 属性位掩码。
    /// 注意：ATTR_CMN_RETURNED_ATTRS 是 getattrlistbulk 的必需位（见 sys/attr.h ATTR_BULK_REQUIRED），
    /// 缺它会让调用直接返回 EINVAL。它会被系统放在返回缓冲区的最前面（attribute_set_t，20 字节）。
    /// 其余位按 attr.h 中 ATTR_CMN_* 的位序排列：NAME(0x1) < FSID(0x4) < OBJTYPE(0x8)
    /// < FILEID(0x02000000)。
    /// CRTIME/MODTIME 未请求：UI 不消费时间戳，省去每条目 32 字节与两次 Date 分配。
    private static let commonattrMask: attrgroup_t =
        attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        | attrgroup_t(ATTR_CMN_NAME)
        | attrgroup_t(ATTR_CMN_FSID)
        | attrgroup_t(ATTR_CMN_OBJTYPE)
        | attrgroup_t(ATTR_CMN_FILEID)

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
        attrList.commonattr = commonattrMask
        attrList.fileattr = attrgroup_t(ATTR_FILE_DATALENGTH)

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

            // 读取当前条目的长度（loadUnaligned，避免对齐约束）
            let entryLength = buffer.withUnsafeBytes { bytes in
                bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
            }

            guard entryLength > 0, offset + Int(entryLength) <= buffer.count else { break }

            let entryEnd = offset + Int(entryLength)

            do {
                let attributes = try parseFileAttributes(
                    buffer: buffer, entryStart: offset, entryEnd: entryEnd, basePath: basePath)
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
     * 从单个条目解析文件信息
     *
     * getattrlistbulk 的每条目布局（按请求位序，系统按 attr.h 的 ATTR_CMN_* 位序返回）：
     *   [UInt32 length]
     *   [attribute_set_t returnedAttrs]   // 20 字节（5 个 attrgroup_t）
     *   [attrreference name]              // 8 字节 (attr_dataoffset + attr_length)
     *   [fsid_t fsid]                     // 8 字节 (int32[2])，若请求了 ATTR_CMN_FSID
     *   [UInt32 objType]                  // 4 字节
     *   [UInt64 fileID]                   // 8 字节，若请求了 ATTR_CMN_FILEID
     *   [Int64 dataLength]               // 8 字节，仅请求了 ATTR_FILE_DATALENGTH 时；对目录该值无意义
     *
     * 关键：attrreference.attr_dataoffset 是相对 **attrreference 字段自身起始** 的偏移，
     * 即 name = buffer + nameRefPos + nameOffset。
     */
    private static func parseFileAttributes(
        buffer: [UInt8], entryStart: Int, entryEnd: Int, basePath: String
    ) throws -> BulkFileAttributes {
        // 用 unsafe pointer 直接按偏移读取，避免逐字段拷贝出 Array 再 withUnsafeBytes。
        // 注意：getattrlistbulk 返回的字段是按 attr.h 的自然对齐布局，但 8 字节字段
        //（FILEID / DATALENGTH）落点可能不是 8 字节对齐。统一用 loadUnaligned 读取
        //（字节级拷贝，无对齐约束）。
        // 闭包内不做 throw，返回 nil 由外部抛错。
        let parsed: ParsedFields? = buffer.withUnsafeBytes { (rawBuf: UnsafeRawBufferPointer) -> ParsedFields? in
            guard let base = rawBuf.baseAddress else { return nil }

            // 跳过 length(4) 与 attribute_set_t(20)
            let nameRefPos = entryStart + 4 + 20
            guard nameRefPos + 8 <= entryEnd else { return nil }

            // NAME: attrreference (offset i32, length u32)
            let nameOffset = Int(rawBuf.loadUnaligned(fromByteOffset: nameRefPos, as: Int32.self))
            let nameLength = Int(rawBuf.loadUnaligned(fromByteOffset: nameRefPos + 4, as: UInt32.self))
            let nameBase = nameRefPos + nameOffset
            guard nameBase + nameLength <= entryEnd, nameLength > 0 else { return nil }
            let namePtr = base.advanced(by: nameBase).assumingMemoryBound(to: CChar.self)
            let fileName = String(cString: namePtr)

            // FSID: fsid_t { int32[2] }
            var p = nameRefPos + 8
            guard p + 8 <= entryEnd else { return nil }
            let fs0 = rawBuf.loadUnaligned(fromByteOffset: p, as: Int32.self)
            let fs1 = rawBuf.loadUnaligned(fromByteOffset: p + 4, as: Int32.self)
            p += 8

            // OBJTYPE
            guard p + 4 <= entryEnd else { return nil }
            let objType = rawBuf.loadUnaligned(fromByteOffset: p, as: UInt32.self)
            p += 4

            // FILEID
            guard p + 8 <= entryEnd else { return nil }
            let fileID = rawBuf.loadUnaligned(fromByteOffset: p, as: UInt64.self)
            p += 8

            // DATALENGTH（仅对普通文件有意义；对目录/符号链接返回的字节数无业务意义，
            // 目录大小由调用方递归累加得到，符号链接的大小不参与统计）
            guard p + 8 <= entryEnd else { return nil }
            let dataLength = rawBuf.loadUnaligned(fromByteOffset: p, as: Int64.self)

            return ParsedFields(
                name: fileName, fs0: fs0, fs1: fs1, objType: objType,
                fileID: fileID, dataLength: dataLength
            )
        }
        guard let f = parsed else { throw FileSystemError.invalidPath }

        let isDirectory = (f.objType == UInt32(VDIR.rawValue))
        let isSymbolicLink = (f.objType == UInt32(VLNK.rawValue))
        let fullPath = (basePath as NSString).appendingPathComponent(f.name)
        // 文件大小：目录与符号链接都记 0（目录靠递归累加；符号链接不参与统计）
        let size: Int64 = (!isDirectory && !isSymbolicLink) ? f.dataLength : 0

        return BulkFileAttributes(
            name: f.name,
            size: size,
            isDirectory: isDirectory,
            isSymbolicLink: isSymbolicLink,
            path: fullPath,
            fsid: (f.fs0, f.fs1),
            fileID: f.fileID
        )
    }

    /// 解析中间结构，仅用于把闭包内的字段读出与构造 BulkFileAttributes 解耦。
    private struct ParsedFields {
        let name: String
        let fs0: Int32
        let fs1: Int32
        let objType: UInt32
        let fileID: UInt64
        let dataLength: Int64
    }
}
