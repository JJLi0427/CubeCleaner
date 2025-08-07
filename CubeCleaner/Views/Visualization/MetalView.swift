//
//  MetalView.swift
//  CubeCleaner
//
//  Created by AI Assistant on 2023-10-01.
//

import SwiftUI
import MetalKit

// SwiftUI wrapper for MTKView
struct MetalView: NSViewRepresentable {
    @ObservedObject var viewModel: VisualizationViewModel
    
    // Coordinator to handle mouse events
    class Coordinator: NSObject {
        var viewModel: VisualizationViewModel
        
        init(viewModel: VisualizationViewModel) {
            self.viewModel = viewModel
        }
        
        // Mouse event handlers
        @objc func handleMouseDown(gesture: NSGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            viewModel.handleMouseDown(at: location)
        }
        
        @objc func handleMouseDragged(gesture: NSPanGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            viewModel.handleMouseDragged(at: location)
        }
        
        @objc func handleMouseUp(gesture: NSGestureRecognizer) {
            viewModel.handleMouseUp()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    func makeNSView(context: Context) -> MTKView {
        // Create MTKView
        let mtkView = MTKView()
        
        // Set up Metal view in view model
        viewModel.setupMetalView(mtkView)
        
        // Add gesture recognizers for mouse events
        let clickGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMouseDown))
        mtkView.addGestureRecognizer(clickGesture)
        
        let panGesture = NSPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMouseDragged))
        mtkView.addGestureRecognizer(panGesture)
        
        let releaseGesture = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleMouseUp))
        releaseGesture.buttonMask = 0x1 // Left mouse button
        releaseGesture.state = .ended
        mtkView.addGestureRecognizer(releaseGesture)
        
        // Set up scroll wheel handling
        NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: mtkView.enclosingScrollView?.contentView,
            queue: nil
        ) { [weak viewModel] _ in
            guard let scrollView = mtkView.enclosingScrollView else { return }
            let delta = scrollView.magnification - 1.0
            viewModel?.handleScroll(delta: CGFloat(delta))
        }
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        // Update view if needed
    }
    
    static func dismantleNSView(_ nsView: MTKView, coordinator: Coordinator) {
        // Clean up resources if needed
    }
}

// Extension to add gesture recognizers to NSView
extension NSView {
    func addGestureRecognizer(_ gestureRecognizer: NSGestureRecognizer) {
        if let gestureRecognizers = self.gestureRecognizers {
            self.gestureRecognizers = gestureRecognizers + [gestureRecognizer]
        } else {
            self.gestureRecognizers = [gestureRecognizer]
        }
    }
}