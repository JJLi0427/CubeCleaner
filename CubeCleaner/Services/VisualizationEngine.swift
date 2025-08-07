//
//  VisualizationEngine.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import Foundation
import Metal
import MetalKit
import SwiftUI

// Protocol defining the visualization engine interface
protocol VisualizationEngineProtocol {
    func prepareVisualizationData(from scanResult: ScanResult, colorScheme: ColorScheme) -> VisualizationData
    func updateVisualization(with data: VisualizationData)
    func zoomTo(item: FileSystemItem)
    func select(item: FileSystemItem?)
    func resetView()
    
    var selectedItem: FileSystemItem? { get }
    var currentViewItems: [FileSystemItem]? { get }
    var renderer: MTKViewDelegate { get }
}

// Data structure for visualization
struct VisualizationData {
    let rootItem: FileSystemItem
    let colorScheme: ColorScheme
    let layoutItems: [LayoutItem]
    
    struct LayoutItem {
        let item: FileSystemItem
        let position: SIMD3<Float>
        let size: SIMD3<Float>
        let color: SIMD4<Float>
        let parentIndex: Int?
        let depth: Int
    }
}

// Main implementation of the visualization engine using Metal
class MetalVisualizationEngine: VisualizationEngineProtocol {
    // Metal properties
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private var pipelineState: MTLRenderPipelineState
    
    // Visualization state
    private var visualizationData: VisualizationData?
    private var vertexBuffer: MTLBuffer?
    private var indexBuffer: MTLBuffer?
    private var uniformBuffer: MTLBuffer?
    
    // Camera and interaction
    private var camera = Camera()
    private var lastMousePosition: CGPoint = .zero
    private var isDragging = false
    private var zoomLevel: Float = 1.0
    private var targetZoomLevel: Float = 1.0
    private var rotationX: Float = 0.0
    private var rotationY: Float = 0.0
    private var targetRotationX: Float = 0.0
    private var targetRotationY: Float = 0.0
    
    // Selection state
    private(set) var selectedItem: FileSystemItem?
    private(set) var currentViewItems: [FileSystemItem]?
    
    // Animation properties
    private var isAnimating = false
    private var animationStartTime: TimeInterval = 0
    private var animationDuration: TimeInterval = 0.5
    private var animationStartCamera = Camera()
    private var animationTargetCamera = Camera()
    
    // Renderer for MTKView
    private(set) lazy var renderer: MTKViewDelegate = CubeRenderer(engine: self)
    
    // MARK: - Initialization
    
    init() {
        // Initialize Metal
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Could not create command queue")
        }
        self.commandQueue = commandQueue
        
        // Load default library
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not create default library")
        }
        self.library = library
        
        // Create pipeline state
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Could not create pipeline state: \(error)")
        }
        
        // Initialize camera
        resetView()
    }
    
    // MARK: - VisualizationEngineProtocol Methods
    
    func prepareVisualizationData(from scanResult: ScanResult, colorScheme: ColorScheme) -> VisualizationData {
        // Create layout items from scan result
        var layoutItems: [VisualizationData.LayoutItem] = []
        
        // Start with the root item
        let rootItem = scanResult.rootItem
        let rootSize = calculateSize(for: rootItem)
        
        // Add root item to layout
        layoutItems.append(VisualizationData.LayoutItem(
            item: rootItem,
            position: SIMD3<Float>(0, 0, 0),
            size: rootSize,
            color: colorForItem(rootItem, scheme: colorScheme),
            parentIndex: nil,
            depth: 0
        ))
        
        // Recursively add children
        if let children = rootItem.children {
            addChildrenToLayout(children, parentIndex: 0, parentItem: rootItem, parentPosition: SIMD3<Float>(0, 0, 0), parentSize: rootSize, layoutItems: &layoutItems, depth: 1, colorScheme: colorScheme)
        }
        
        // Create and return visualization data
        let data = VisualizationData(rootItem: rootItem, colorScheme: colorScheme, layoutItems: layoutItems)
        self.visualizationData = data
        self.currentViewItems = [rootItem] + (rootItem.children ?? [])
        
        // Prepare buffers
        prepareBuffers(for: data)
        
        return data
    }
    
    func updateVisualization(with data: VisualizationData) {
        self.visualizationData = data
        prepareBuffers(for: data)
    }
    
    func zoomTo(item: FileSystemItem) {
        guard let data = visualizationData else { return }
        
        // Find the layout item for the given file system item
        guard let layoutItemIndex = data.layoutItems.firstIndex(where: { $0.item.id == item.id }) else { return }
        let layoutItem = data.layoutItems[layoutItemIndex]
        
        // Set up animation
        animationStartTime = CACurrentMediaTime()
        animationStartCamera = camera
        
        // Calculate target camera position
        let targetPosition = layoutItem.position
        let targetSize = layoutItem.size
        let distance = max(targetSize.x, max(targetSize.y, targetSize.z)) * 2.0
        
        // Create target camera
        animationTargetCamera = Camera(
            position: SIMD3<Float>(targetPosition.x, targetPosition.y, targetPosition.z + distance),
            target: targetPosition,
            up: SIMD3<Float>(0, 1, 0)
        )
        
        // Update current view items
        if item.isDirectory {
            currentViewItems = [item] + (item.children ?? [])
        } else {
            currentViewItems = [item]
        }
        
        isAnimating = true
    }
    
    func select(item: FileSystemItem?) {
        selectedItem = item
    }
    
    func resetView() {
        // Reset camera to default position
        camera = Camera(
            position: SIMD3<Float>(0, 0, 5),
            target: SIMD3<Float>(0, 0, 0),
            up: SIMD3<Float>(0, 1, 0)
        )
        
        zoomLevel = 1.0
        targetZoomLevel = 1.0
        rotationX = 0.0
        rotationY = 0.0
        targetRotationX = 0.0
        targetRotationY = 0.0
        
        // Reset current view items to root and its children
        if let rootItem = visualizationData?.rootItem {
            currentViewItems = [rootItem] + (rootItem.children ?? [])
        }
    }
    
    // MARK: - Private Methods
    
    private func prepareBuffers(for data: VisualizationData) {
        // Create vertices and indices for cubes
        var vertices: [Vertex] = []
        var indices: [UInt16] = []
        
        for layoutItem in data.layoutItems {
            let cubeVertices = createCubeVertices(position: layoutItem.position, size: layoutItem.size, color: layoutItem.color)
            let baseIndex = UInt16(vertices.count)
            
            vertices.append(contentsOf: cubeVertices)
            
            // Add indices for the cube (12 triangles, 36 indices)
            let cubeIndices: [UInt16] = [
                // Front face
                baseIndex + 0, baseIndex + 1, baseIndex + 2,
                baseIndex + 2, baseIndex + 3, baseIndex + 0,
                // Right face
                baseIndex + 1, baseIndex + 5, baseIndex + 6,
                baseIndex + 6, baseIndex + 2, baseIndex + 1,
                // Back face
                baseIndex + 5, baseIndex + 4, baseIndex + 7,
                baseIndex + 7, baseIndex + 6, baseIndex + 5,
                // Left face
                baseIndex + 4, baseIndex + 0, baseIndex + 3,
                baseIndex + 3, baseIndex + 7, baseIndex + 4,
                // Top face
                baseIndex + 3, baseIndex + 2, baseIndex + 6,
                baseIndex + 6, baseIndex + 7, baseIndex + 3,
                // Bottom face
                baseIndex + 4, baseIndex + 5, baseIndex + 1,
                baseIndex + 1, baseIndex + 0, baseIndex + 4
            ]
            
            indices.append(contentsOf: cubeIndices)
        }
        
        // Create vertex buffer
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Vertex>.stride, options: [])
        
        // Create index buffer
        indexBuffer = device.makeBuffer(bytes: indices, length: indices.count * MemoryLayout<UInt16>.stride, options: [])
        
        // Create uniform buffer
        let uniforms = Uniforms(modelViewProjectionMatrix: camera.viewProjectionMatrix)
        uniformBuffer = device.makeBuffer(bytes: [uniforms], length: MemoryLayout<Uniforms>.stride, options: [])
    }
    
    private func createCubeVertices(position: SIMD3<Float>, size: SIMD3<Float>, color: SIMD4<Float>) -> [Vertex] {
        let halfWidth = size.x / 2
        let halfHeight = size.y / 2
        let halfDepth = size.z / 2
        
        return [
            // Front face
            Vertex(position: SIMD3<Float>(position.x - halfWidth, position.y - halfHeight, position.z + halfDepth), color: color),
            Vertex(position: SIMD3<Float>(position.x + halfWidth, position.y - halfHeight, position.z + halfDepth), color: color),
            Vertex(position: SIMD3<Float>(position.x + halfWidth, position.y + halfHeight, position.z + halfDepth), color: color),
            Vertex(position: SIMD3<Float>(position.x - halfWidth, position.y + halfHeight, position.z + halfDepth), color: color),
            
            // Back face
            Vertex(position: SIMD3<Float>(position.x - halfWidth, position.y - halfHeight, position.z - halfDepth), color: color),
            Vertex(position: SIMD3<Float>(position.x + halfWidth, position.y - halfHeight, position.z - halfDepth), color: color),
            Vertex(position: SIMD3<Float>(position.x + halfWidth, position.y + halfHeight, position.z - halfDepth), color: color),
            Vertex(position: SIMD3<Float>(position.x - halfWidth, position.y + halfHeight, position.z - halfDepth), color: color)
        ]
    }
    
    private func addChildrenToLayout(
        _ children: [FileSystemItem],
        parentIndex: Int,
        parentItem: FileSystemItem,
        parentPosition: SIMD3<Float>,
        parentSize: SIMD3<Float>,
        layoutItems: inout [VisualizationData.LayoutItem],
        depth: Int,
        colorScheme: ColorScheme
    ) {
        // Skip if parent is too small or we're too deep
        if max(parentSize.x, max(parentSize.y, parentSize.z)) < 0.01 || depth > 5 {
            return
        }
        
        // Sort children by size (largest first)
        let sortedChildren = children.sorted { $0.size > $1.size }
        
        // Calculate total size of children
        let totalChildrenSize = sortedChildren.reduce(0) { $0 + $1.size }
        
        // Skip if total size is zero
        if totalChildrenSize == 0 {
            return
        }
        
        // Use treemap algorithm to layout children within parent
        let layout = calculateTreemapLayout(items: sortedChildren, parentSize: parentSize, parentPosition: parentPosition)
        
        // Add each child to the layout
        for (index, (child, childLayout)) in zip(sortedChildren, layout).enumerated() {
            let childPosition = childLayout.position
            let childSize = childLayout.size
            
            // Add child to layout items
            let childIndex = layoutItems.count
            layoutItems.append(VisualizationData.LayoutItem(
                item: child,
                position: childPosition,
                size: childSize,
                color: colorForItem(child, scheme: colorScheme),
                parentIndex: parentIndex,
                depth: depth
            ))
            
            // Recursively add grandchildren if this is a directory
            if let grandchildren = child.children {
                addChildrenToLayout(grandchildren, parentIndex: childIndex, parentItem: child, parentPosition: childPosition, parentSize: childSize, layoutItems: &layoutItems, depth: depth + 1, colorScheme: colorScheme)
            }
        }
    }
    
    private func calculateSize(for item: FileSystemItem) -> SIMD3<Float> {
        // Base size on the cube root of the item's size
        let volume = Float(item.size)
        let sideLength = cbrt(volume) * 0.001 // Scale factor to make sizes reasonable
        
        return SIMD3<Float>(sideLength, sideLength, sideLength)
    }
    
    private func colorForItem(_ item: FileSystemItem, scheme: ColorScheme) -> SIMD4<Float> {
        switch scheme {
        case .fileType:
            // Color based on file type
            return colorForFileType(item.type)
            
        case .modificationDate:
            // Color based on modification date (age)
            return colorForAge(item.ageInDays)
            
        case .size:
            // Color based on size
            return colorForSize(item.size)
            
        case .parentFolder:
            // Color based on parent folder
            return colorForParentFolder(item)
            
        default:
            // Default color
            return SIMD4<Float>(0.7, 0.7, 0.7, 1.0)
        }
    }
    
    private func colorForFileType(_ type: FileType) -> SIMD4<Float> {
        switch type {
        case .folder:
            return SIMD4<Float>(0.2, 0.4, 0.8, 1.0) // Blue
        case .document:
            return SIMD4<Float>(0.2, 0.8, 0.2, 1.0) // Green
        case .image:
            return SIMD4<Float>(0.8, 0.2, 0.8, 1.0) // Purple
        case .video:
            return SIMD4<Float>(0.8, 0.4, 0.6, 1.0) // Pink
        case .audio:
            return SIMD4<Float>(0.8, 0.6, 0.2, 1.0) // Orange
        case .archive:
            return SIMD4<Float>(0.8, 0.8, 0.2, 1.0) // Yellow
        case .application:
            return SIMD4<Float>(0.5, 0.5, 0.5, 1.0) // Gray
        case .system:
            return SIMD4<Float>(0.8, 0.2, 0.2, 1.0) // Red
        case .other:
            return SIMD4<Float>(0.7, 0.7, 0.7, 1.0) // Light Gray
        }
    }
    
    private func colorForAge(_ ageInDays: Int) -> SIMD4<Float> {
        // Color gradient from green (new) to red (old)
        let normalizedAge = min(Float(ageInDays) / 365.0, 1.0) // Normalize to 0-1 over a year
        
        return SIMD4<Float>(
            normalizedAge,           // Red component (increases with age)
            1.0 - normalizedAge,     // Green component (decreases with age)
            0.2,                     // Blue component (constant)
            1.0                      // Alpha
        )
    }
    
    private func colorForSize(_ size: Int64) -> SIMD4<Float> {
        // Color gradient from blue (small) to red (large)
        // Use log scale because file sizes vary by orders of magnitude
        let logSize = log10(Float(max(1, size)))
        let normalizedSize = min(logSize / 9.0, 1.0) // 10^9 bytes = ~1GB
        
        return SIMD4<Float>(
            normalizedSize,          // Red component (increases with size)
            0.2,                     // Green component (constant)
            1.0 - normalizedSize,    // Blue component (decreases with size)
            1.0                      // Alpha
        )
    }
    
    private func colorForParentFolder(_ item: FileSystemItem) -> SIMD4<Float> {
        // Generate a color based on the hash of the parent folder name
        let parentName = item.url.deletingLastPathComponent().lastPathComponent
        let hash = abs(parentName.hash)
        
        // Use the hash to generate RGB values between 0.2 and 0.8
        let r = Float(hash % 1000) / 1000.0 * 0.6 + 0.2
        let g = Float((hash / 1000) % 1000) / 1000.0 * 0.6 + 0.2
        let b = Float((hash / 1000000) % 1000) / 1000.0 * 0.6 + 0.2
        
        return SIMD4<Float>(r, g, b, 1.0)
    }
    
    private func calculateTreemapLayout(items: [FileSystemItem], parentSize: SIMD3<Float>, parentPosition: SIMD3<Float>) -> [(position: SIMD3<Float>, size: SIMD3<Float>)] {
        // Simplified treemap layout algorithm
        // In a real implementation, you'd use a more sophisticated algorithm like "squarified treemap"
        
        // Calculate total size
        let totalSize = items.reduce(0) { $0 + $1.size }
        guard totalSize > 0 else { return [] }
        
        var result: [(position: SIMD3<Float>, size: SIMD3<Float>)] = []
        
        // Determine which dimension to split along (use the largest)
        let splitDimension: Int
        if parentSize.x >= parentSize.y && parentSize.x >= parentSize.z {
            splitDimension = 0 // Split along X
        } else if parentSize.y >= parentSize.x && parentSize.y >= parentSize.z {
            splitDimension = 1 // Split along Y
        } else {
            splitDimension = 2 // Split along Z
        }
        
        // Calculate positions and sizes for each item
        var offset: Float = 0
        for item in items {
            let ratio = Float(item.size) / Float(totalSize)
            let itemSize = calculateSize(for: item)
            
            var position = parentPosition
            
            // Position based on split dimension
            if splitDimension == 0 {
                position.x = parentPosition.x - parentSize.x/2 + offset + itemSize.x/2
                offset += itemSize.x
            } else if splitDimension == 1 {
                position.y = parentPosition.y - parentSize.y/2 + offset + itemSize.y/2
                offset += itemSize.y
            } else {
                position.z = parentPosition.z - parentSize.z/2 + offset + itemSize.z/2
                offset += itemSize.z
            }
            
            result.append((position: position, size: itemSize))
        }
        
        return result
    }
    
    // MARK: - Rendering
    
    func render(in view: MTKView, commandBuffer: MTLCommandBuffer) {
        guard let renderPassDescriptor = view.currentRenderPassDescriptor,
              let vertexBuffer = vertexBuffer,
              let indexBuffer = indexBuffer,
              let uniformBuffer = uniformBuffer else {
            return
        }
        
        // Update camera if animating
        if isAnimating {
            updateAnimation()
        }
        
        // Update uniform buffer with current camera
        let uniforms = Uniforms(modelViewProjectionMatrix: camera.viewProjectionMatrix)
        uniformBuffer.contents().copyMemory(from: &uniforms, byteCount: MemoryLayout<Uniforms>.stride)
        
        // Create render command encoder
        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(uniformBuffer, offset: 0, index: 1)
        
        // Draw indexed primitives
        let indexCount = indexBuffer.length / MemoryLayout<UInt16>.stride
        renderEncoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
        
        renderEncoder.endEncoding()
    }
    
    private func updateAnimation() {
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - animationStartTime
        
        if elapsed >= animationDuration {
            // Animation complete
            camera = animationTargetCamera
            isAnimating = false
            return
        }
        
        // Calculate interpolation factor (0 to 1)
        let t = Float(elapsed / animationDuration)
        
        // Use smooth step for easing
        let smoothT = t * t * (3 - 2 * t)
        
        // Interpolate camera position
        camera.position = mix(
            animationStartCamera.position,
            animationTargetCamera.position,
            t: smoothT
        )
        
        // Interpolate camera target
        camera.target = mix(
            animationStartCamera.target,
            animationTargetCamera.target,
            t: smoothT
        )
    }
    
    // MARK: - Input Handling
    
    func handleMouseDown(at point: CGPoint) {
        lastMousePosition = point
        isDragging = true
    }
    
    func handleMouseDragged(at point: CGPoint) {
        guard isDragging else { return }
        
        let deltaX = Float(point.x - lastMousePosition.x) * 0.01
        let deltaY = Float(point.y - lastMousePosition.y) * 0.01
        
        targetRotationY += deltaX
        targetRotationX += deltaY
        
        // Apply rotation to camera
        updateCameraRotation()
        
        lastMousePosition = point
    }
    
    func handleMouseUp() {
        isDragging = false
    }
    
    func handleScroll(delta: CGFloat) {
        targetZoomLevel *= Float(1.0 - delta * 0.1)
        targetZoomLevel = max(0.1, min(targetZoomLevel, 10.0))
        
        // Apply zoom to camera
        updateCameraZoom()
    }
    
    private func updateCameraRotation() {
        // Smoothly interpolate current rotation towards target
        rotationX += (targetRotationX - rotationX) * 0.1
        rotationY += (targetRotationY - rotationY) * 0.1
        
        // Apply rotation to camera
        let distance = length(camera.position - camera.target)
        
        let rotationMatrix = matrix_float4x4(rotationY: rotationY) * matrix_float4x4(rotationX: rotationX)
        let offset = rotationMatrix * SIMD4<Float>(0, 0, distance, 1)
        
        camera.position = camera.target + SIMD3<Float>(offset.x, offset.y, offset.z)
    }
    
    private func updateCameraZoom() {
        // Smoothly interpolate current zoom towards target
        zoomLevel += (targetZoomLevel - zoomLevel) * 0.1
        
        // Apply zoom to camera
        let direction = normalize(camera.position - camera.target)
        let distance = length(camera.position - camera.target)
        let targetDistance = distance * zoomLevel
        
        camera.position = camera.target + direction * targetDistance
    }
}

// MARK: - Supporting Types

// Vertex structure for Metal
struct Vertex {
    let position: SIMD3<Float>
    let color: SIMD4<Float>
}

// Uniforms structure for Metal
struct Uniforms {
    let modelViewProjectionMatrix: matrix_float4x4
}

// Camera class for 3D navigation
class Camera {
    var position: SIMD3<Float>
    var target: SIMD3<Float>
    var up: SIMD3<Float>
    
    init(position: SIMD3<Float> = SIMD3<Float>(0, 0, 5),
         target: SIMD3<Float> = SIMD3<Float>(0, 0, 0),
         up: SIMD3<Float> = SIMD3<Float>(0, 1, 0)) {
        self.position = position
        self.target = target
        self.up = up
    }
    
    var viewMatrix: matrix_float4x4 {
        return matrix_look_at_right_hand(position, target, up)
    }
    
    var projectionMatrix: matrix_float4x4 {
        return matrix_perspective_right_hand(Float.pi / 3, 1, 0.1, 100)
    }
    
    var viewProjectionMatrix: matrix_float4x4 {
        return projectionMatrix * viewMatrix
    }
}

// Metal renderer for MTKView
class CubeRenderer: NSObject, MTKViewDelegate {
    private let engine: MetalVisualizationEngine
    
    init(engine: MetalVisualizationEngine) {
        self.engine = engine
        super.init()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Handle view size changes
    }
    
    func draw(in view: MTKView) {
        guard let commandQueue = engine.commandQueue,
              let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        engine.render(in: view, commandBuffer: commandBuffer)
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        
        commandBuffer.commit()
    }
}

// MARK: - Matrix Math Extensions

// Matrix utility functions
func matrix_look_at_right_hand(_ eye: SIMD3<Float>, _ center: SIMD3<Float>, _ up: SIMD3<Float>) -> matrix_float4x4 {
    let z = normalize(eye - center)
    let x = normalize(cross(up, z))
    let y = cross(z, x)
    
    let translateMatrix = matrix_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(-eye.x, -eye.y, -eye.z, 1)
    )
    
    let rotateMatrix = matrix_float4x4(
        SIMD4<Float>(x.x, y.x, z.x, 0),
        SIMD4<Float>(x.y, y.y, z.y, 0),
        SIMD4<Float>(x.z, y.z, z.z, 0),
        SIMD4<Float>(0, 0, 0, 1)
    )
    
    return rotateMatrix * translateMatrix
}

func matrix_perspective_right_hand(_ fovyRadians: Float, _ aspect: Float, _ nearZ: Float, _ farZ: Float) -> matrix_float4x4 {
    let ys = 1 / tanf(fovyRadians * 0.5)
    let xs = ys / aspect
    let zs = farZ / (nearZ - farZ)
    
    return matrix_float4x4(
        SIMD4<Float>(xs, 0, 0, 0),
        SIMD4<Float>(0, ys, 0, 0),
        SIMD4<Float>(0, 0, zs, -1),
        SIMD4<Float>(0, 0, nearZ * zs, 0)
    )
}

extension matrix_float4x4 {
    init(rotationX angle: Float) {
        let c = cosf(angle)
        let s = sinf(angle)
        
        self.init(
            SIMD4<Float>(1, 0, 0, 0),
            SIMD4<Float>(0, c, s, 0),
            SIMD4<Float>(0, -s, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
    
    init(rotationY angle: Float) {
        let c = cosf(angle)
        let s = sinf(angle)
        
        self.init(
            SIMD4<Float>(c, 0, -s, 0),
            SIMD4<Float>(0, 1, 0, 0),
            SIMD4<Float>(s, 0, c, 0),
            SIMD4<Float>(0, 0, 0, 1)
        )
    }
}

func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, t: Float) -> SIMD3<Float> {
    return a * (1 - t) + b * t
}