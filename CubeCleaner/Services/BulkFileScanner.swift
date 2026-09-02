// BulkFileScanner.swift — 批量文件扫描器

import Darwin
import Foundation

// MARK: - 批量文件属性结构
struct BulkFileAttributes {
    let name: String
    let size: Int64
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let path: String
    /// 文件所在卷的 fsid（int32 对）。非 APFS 或解析失败时为 nil。
    let fsid: (Int32, Int32)?
    /// 对象 id（APFS 上为 inode 号），用于硬链接/firmlink 去重。不可靠或不存在时为 nil。
    let fileID: UInt64?
}

// MARK: - 批量文件扫描器
/// 使用 getattrlistbulk 一次性读取多个文件属性，减少系统调用。
class BulkFileScanner {

    private static let batchSize: Int = 512
    private static let bufferSize: Int = 64 * 1024

    /// 请求的 common 属性位掩码。
    /// ATTR_CMN_RETURNED_ATTRS 是 getattrlistbulk 的必需位（缺它直接返回 EINVAL），
    /// 系统会把它放在返回缓冲区最前面（attribute_set_t，20 字节）。
    /// 其余位按 attr.h 位序：NAME < FSID < OBJTYPE < FILEID。
    /// CRTIME/MODTIME 未请求：UI 不消费时间戳。
    private static let commonattrMask: attrgroup_t =
        attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        | attrgroup_t(ATTR_CMN_NAME)
        | attrgroup_t(ATTR_CMN_FSID)
        | attrgroup_t(ATTR_CMN_OBJTYPE)
        | attrgroup_t(ATTR_CMN_FILEID)

    /// 批量扫描目录内容，返回文件属性数组。
    static func scanDirectory(at directoryPath: String) throws -> [BulkFileAttributes] {
        let dirFD = open(directoryPath, O_RDONLY)
        guard dirFD >= 0 else {
            throw POSIXError(.EACCES)
        }
        defer { close(dirFD) }

        var attrList = attrlist()
        attrList.bitmapcount = UInt16(ATTR_BIT_MAP_COUNT)
        attrList.commonattr = commonattrMask
        attrList.fileattr = attrgroup_t(ATTR_FILE_DATALENGTH)

        var fileAttributes: [BulkFileAttributes] = []
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while true {
            let count = buffer.withUnsafeMutableBytes { bufferPtr in
                getattrlistbulk(dirFD, &attrList, bufferPtr.baseAddress, bufferPtr.count, 0)
            }

            if count == 0 {
                break
            }

            if count < 0 {
                let error = errno
                if error == ENOENT || error == ENOTDIR {
                    break
                }
                throw POSIXError(POSIXErrorCode(rawValue: error) ?? .EACCES)
            }

            let parsedFiles = try parseAttributeBuffer(
                buffer, count: Int(count), basePath: directoryPath)
            fileAttributes.append(contentsOf: parsedFiles)

            if count < batchSize {
                break
            }
        }

        return fileAttributes
    }

    /// 解析 getattrlistbulk 返回的缓冲区。
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
     * 从单个条目解析文件信息。
     *
     * getattrlistbulk 的每条目布局（按请求位序）：
     *   [UInt32 length]
     *   [attribute_set_t returnedAttrs]   // 20 字节
     *   [attrreference name]              // 8 字节 (offset + length)
     *   [fsid_t fsid]                     // 8 字节
     *   [UInt32 objType]                  // 4 字节
     *   [UInt64 fileID]                   // 8 字节
     *   [Int64 dataLength]                // 8 字节
     *
     * attrreference.attr_dataoffset 是相对 attrreference 字段自身起始的偏移。
     */
    private static func parseFileAttributes(
        buffer: [UInt8], entryStart: Int, entryEnd: Int, basePath: String
    ) throws -> BulkFileAttributes {
        // 用 unsafe pointer 按偏移读取；8 字节字段落点可能不对齐，统一用 loadUnaligned。
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

            // DATALENGTH（对目录/符号链接无业务意义，目录大小由递归累加）
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
        // 目录与符号链接大小记 0（目录靠递归累加；符号链接不参与统计）
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

    /// 解析中间结构，用于把闭包内字段读出与构造 BulkFileAttributes 解耦。
    private struct ParsedFields {
        let name: String
        let fs0: Int32
        let fs1: Int32
        let objType: UInt32
        let fileID: UInt64
        let dataLength: Int64
    }
}
