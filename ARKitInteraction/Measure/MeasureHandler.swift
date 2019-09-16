//
//  MeasureHandler.swift
//  ARKitInteraction
//
//  Created by Karthi on 16/09/19.
//  Copyright © 2019 Apple. All rights reserved.
//
import ARKit
import UIKit

protocol MeasureHandlerDelegate {
    func updateFocusSquare()
    func measureSession(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera)
}

class MeasureHandler: NSObject, ARSCNViewDelegate, ARSessionDelegate {

    var delegate: MeasureHandlerDelegate? = nil
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        DispatchQueue.main.async { [weak self] in
            guard let strongSelf = self else { return }
            strongSelf.delegate?.updateFocusSquare()
        }
    }

    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        delegate?.measureSession(session, cameraDidChangeTrackingState: camera)
    }
    
}
