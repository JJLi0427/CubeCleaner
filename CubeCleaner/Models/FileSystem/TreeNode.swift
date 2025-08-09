//
//  TreeNode.swift
//  CubeCleaner
//
//  Created by GitHub Copilot on 2025/8/9.
//

import Foundation

/// 树状图数据结构的节点类
/// 用于构建文件系统的层次结构，支持树状图布局算法
@Observable
class TreeNode: Identifiable, Hashable {
    // MARK: - Properties
    
    /// 唯一标识符
    let id = UUID()
    
    /// 关联的文件系统项目
    let fileSystemItem: FileSystemItem
    
    /// 父节点
    weak var parent: TreeNode?
    
    /// 子节点集合
    private(set) var children: [TreeNode] = []
    
    /// 节点值（用于树状图布局，通常是文件大小）
    var value: Double {
        return Double(fileSystemItem.totalSize)
    }
    
    /// 节点深度（从根节点开始）
    var depth: Int {
        var currentDepth = 0
        var current = parent
        while current != nil {
            currentDepth += 1
            current = current?.parent
        }
        return currentDepth
    }
    
    /// 是否为叶子节点
    var isLeaf: Bool {
        return children.isEmpty
    }
    
    /// 是否为根节点
    var isRoot: Bool {
        return parent == nil
    }
    
    /// 子节点总数（递归计算）
    var totalChildCount: Int {
        return children.count + children.reduce(0) { $0 + $1.totalChildCount }
    }
    
    /// 叶子节点数量
    var leafCount: Int {
        if isLeaf {
            return 1
        }
        return children.reduce(0) { $0 + $1.leafCount }
    }
    
    // MARK: - Layout Properties (for TreeMap)
    
    /// 布局矩形
    var layoutRect: CGRect = .zero
    
    /// 是否已计算布局
    var isLayoutCalculated: Bool = false
    
    /// 在父节点中的相对权重
    var weight: Double {
        guard let parent = parent else { return 1.0 }
        let totalParentValue = parent.children.reduce(0) { $0 + $1.value }
        return totalParentValue > 0 ? value / totalParentValue : 0
    }
    
    // MARK: - Initialization
    
    /// 初始化树节点
    /// - Parameter fileSystemItem: 关联的文件系统项目
    init(fileSystemItem: FileSystemItem) {
        self.fileSystemItem = fileSystemItem
    }
    
    /// 从文件系统项目构建树节点
    /// - Parameter fileSystemItem: 根文件系统项目
    /// - Returns: 构建的树节点
    static func build(from fileSystemItem: FileSystemItem) -> TreeNode {
        let node = TreeNode(fileSystemItem: fileSystemItem)
        
        // 递归构建子节点
        for child in fileSystemItem.children {
            let childNode = TreeNode.build(from: child)
            node.addChild(childNode)
        }
        
        return node
    }
    
    // MARK: - Tree Management
    
    /// 添加子节点
    /// - Parameter child: 要添加的子节点
    func addChild(_ child: TreeNode) {
        child.parent = self
        children.append(child)
        
        // 重置布局标记
        resetLayoutCalculation()
    }
    
    /// 移除子节点
    /// - Parameter child: 要移除的子节点
    func removeChild(_ child: TreeNode) {
        children.removeAll { $0.id == child.id }
        child.parent = nil
        
        // 重置布局标记
        resetLayoutCalculation()
    }
    
    /// 移除所有子节点
    func removeAllChildren() {
        for child in children {
            child.parent = nil
        }
        children.removeAll()
        
        // 重置布局标记
        resetLayoutCalculation()
    }
    
    /// 插入子节点到指定位置
    /// - Parameters:
    ///   - child: 要插入的子节点
    ///   - index: 插入位置
    func insertChild(_ child: TreeNode, at index: Int) {
        child.parent = self
        children.insert(child, at: index)
        
        // 重置布局标记
        resetLayoutCalculation()
    }
    
    // MARK: - Tree Traversal
    
    /// 前序遍历（深度优先）
    /// - Parameter visit: 访问节点的闭包
    func preorderTraversal(_ visit: (TreeNode) -> Void) {
        visit(self)
        for child in children {
            child.preorderTraversal(visit)
        }
    }
    
    /// 后序遍历
    /// - Parameter visit: 访问节点的闭包
    func postorderTraversal(_ visit: (TreeNode) -> Void) {
        for child in children {
            child.postorderTraversal(visit)
        }
        visit(self)
    }
    
    /// 层序遍历（广度优先）
    /// - Parameter visit: 访问节点的闭包
    func levelOrderTraversal(_ visit: (TreeNode) -> Void) {
        var queue: [TreeNode] = [self]
        
        while !queue.isEmpty {
            let node = queue.removeFirst()
            visit(node)
            queue.append(contentsOf: node.children)
        }
    }
    
    /// 查找符合条件的节点
    /// - Parameter predicate: 查找条件
    /// - Returns: 找到的第一个节点，没找到返回 nil
    func find(_ predicate: (TreeNode) -> Bool) -> TreeNode? {
        if predicate(self) {
            return self
        }
        
        for child in children {
            if let found = child.find(predicate) {
                return found
            }
        }
        
        return nil
    }
    
    /// 查找所有符合条件的节点
    /// - Parameter predicate: 查找条件
    /// - Returns: 找到的所有节点
    func findAll(_ predicate: (TreeNode) -> Bool) -> [TreeNode] {
        var results: [TreeNode] = []
        
        if predicate(self) {
            results.append(self)
        }
        
        for child in children {
            results.append(contentsOf: child.findAll(predicate))
        }
        
        return results
    }
    
    // MARK: - Filtering and Sorting
    
    /// 按大小排序子节点（降序）
    func sortChildrenBySize() {
        children.sort { $0.value > $1.value }
        
        // 递归排序子节点
        for child in children {
            child.sortChildrenBySize()
        }
        
        // 重置布局标记
        resetLayoutCalculation()
    }
    
    /// 按名称排序子节点
    func sortChildrenByName() {
        children.sort { $0.fileSystemItem.name < $1.fileSystemItem.name }
        
        // 递归排序子节点
        for child in children {
            child.sortChildrenByName()
        }
        
        // 重置布局标记
        resetLayoutCalculation()
    }
    
    /// 按文件类型排序子节点
    func sortChildrenByType() {
        children.sort { 
            // 文件夹优先
            if $0.fileSystemItem.isDirectory != $1.fileSystemItem.isDirectory {
                return $0.fileSystemItem.isDirectory
            }
            // 然后按文件类型
            return $0.fileSystemItem.fileType.rawValue < $1.fileSystemItem.fileType.rawValue
        }
        
        // 递归排序子节点
        for child in children {
            child.sortChildrenByType()
        }
        
        // 重置布局标记
        resetLayoutCalculation()
    }
    
    /// 过滤子节点
    /// - Parameter predicate: 过滤条件
    /// - Returns: 过滤后的新树节点
    func filter(_ predicate: (TreeNode) -> Bool) -> TreeNode? {
        let filteredNode = TreeNode(fileSystemItem: fileSystemItem)
        
        for child in children {
            if predicate(child) {
                // 如果子节点符合条件，递归过滤其子节点
                if let filteredChild = child.filter(predicate) {
                    filteredNode.addChild(filteredChild)
                }
            } else {
                // 如果子节点不符合条件，但其子节点可能符合条件
                if let filteredChild = child.filter(predicate), !filteredChild.children.isEmpty {
                    filteredNode.addChild(filteredChild)
                }
            }
        }
        
        // 如果自己不符合条件且没有符合条件的子节点，返回 nil
        if !predicate(self) && filteredNode.children.isEmpty {
            return nil
        }
        
        return filteredNode
    }
    
    // MARK: - Layout Management
    
    /// 设置布局矩形
    /// - Parameter rect: 布局矩形
    func setLayoutRect(_ rect: CGRect) {
        layoutRect = rect
        isLayoutCalculated = true
    }
    
    /// 重置布局计算标记
    func resetLayoutCalculation() {
        isLayoutCalculated = false
        layoutRect = .zero
        
        // 递归重置子节点
        for child in children {
            child.resetLayoutCalculation()
        }
    }
    
    /// 获取所有需要显示的叶子节点（用于树状图渲染）
    var displayableLeaves: [TreeNode] {
        if isLeaf {
            return [self]
        }
        
        return children.flatMap { $0.displayableLeaves }
    }
    
    // MARK: - Path Operations
    
    /// 获取从根节点到当前节点的路径
    var pathFromRoot: [TreeNode] {
        var path: [TreeNode] = []
        var current: TreeNode? = self
        
        while let node = current {
            path.insert(node, at: 0)
            current = node.parent
        }
        
        return path
    }
    
    /// 获取节点的相对路径字符串
    var relativePath: String {
        let pathNodes = pathFromRoot
        if pathNodes.count <= 1 {
            return fileSystemItem.name
        }
        
        return pathNodes.dropFirst().map { $0.fileSystemItem.name }.joined(separator: "/")
    }
    
    // MARK: - Hashable & Equatable
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        return lhs.id == rhs.id
    }
}

// MARK: - Extensions

extension TreeNode: CustomStringConvertible {
    var description: String {
        return "TreeNode(name: \(fileSystemItem.name), size: \(fileSystemItem.totalSize), children: \(children.count))"
    }
}

extension TreeNode {
    /// 打印树结构（调试用）
    /// - Parameter prefix: 前缀字符串
    func printTree(prefix: String = "") {
        print("\(prefix)\(fileSystemItem.name) (\(ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)))")
        
        for (index, child) in children.enumerated() {
            let isLast = index == children.count - 1
            let childPrefix = prefix + (isLast ? "└── " : "├── ")
            let grandChildPrefix = prefix + (isLast ? "    " : "│   ")
            
            print(childPrefix, terminator: "")
            child.printTree(prefix: grandChildPrefix)
        }
    }
}
