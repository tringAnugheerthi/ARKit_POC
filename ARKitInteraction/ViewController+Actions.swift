/*
See LICENSE folder for this sample’s licensing information.

Abstract:
UI Actions for the main view controller.
*/

import UIKit
import SceneKit

extension ViewController: UIGestureRecognizerDelegate {
    
    enum SegueIdentifier: String {
        case showObjects
    }
    
    // MARK: - Interface Actions
    
    /// Displays the `VirtualObjectSelectionViewController` from the `addObjectButton` or in response to a tap gesture in the `sceneView`.
    @IBAction func showVirtualObjectSelectionViewController() {
        
        // Ensure adding objects is an available action and we are not loading another object (to avoid concurrent modifications of the scene).
        guard !addObjectButton.isHidden && !virtualObjectLoader.isLoading else { return }
        
        statusViewController.cancelScheduledMessage(for: .contentPlacement)
        performSegue(withIdentifier: SegueIdentifier.showObjects.rawValue, sender: addObjectButton)
    }
    
    /// Determines if the tap gesture for presenting the `VirtualObjectSelectionViewController` should be used.
    func gestureRecognizerShouldBegin(_: UIGestureRecognizer) -> Bool {
        return virtualObjectLoader.loadedObjects.isEmpty || measureSwitch.isOn
    }
    
    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        return true
    }
    
    /// - Tag: restartExperience
    func restartExperience() {
        guard isRestartAvailable, !virtualObjectLoader.isLoading else { return }
        isRestartAvailable = false

        statusViewController.cancelAllScheduledMessages()

        virtualObjectLoader.removeAllVirtualObjects()
        addObjectButton.setImage(#imageLiteral(resourceName: "add"), for: [])
        addObjectButton.setImage(#imageLiteral(resourceName: "addPressed"), for: [.highlighted])

        resetTracking()

        // Disable restart for a while in order to give the session time to restart.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            self.isRestartAvailable = true
            self.upperControlsView.isHidden = false
        }
    }
}

extension ViewController: UIPopoverPresentationControllerDelegate {
    
    // MARK: - UIPopoverPresentationControllerDelegate

    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if let objectDetectionVC = segue.destination as? ObjectDetectionViewController {
            self.objectDetectionVC = objectDetectionVC
            return
        }
//        if let measureVC = segue.destination as? MeasureViewController {
//            measureVC.sceneView = sceneView
//        }
        // All menus should be popovers (even on iPhone).
        if let popoverController = segue.destination.popoverPresentationController, let button = sender as? UIButton {
            popoverController.delegate = self
            popoverController.sourceView = button
            popoverController.sourceRect = button.bounds
        }
        
        guard let identifier = segue.identifier,
              let segueIdentifer = SegueIdentifier(rawValue: identifier),
              segueIdentifer == .showObjects else { return }
        
        let objectsViewController = segue.destination as! VirtualObjectSelectionViewController
        objectsViewController.virtualObjects = VirtualObject.availableObjects
        objectsViewController.delegate = self
        self.objectsViewController = objectsViewController
        
        // Set all rows of currently placed objects to selected.
        for object in virtualObjectLoader.loadedObjects {
            guard let index = VirtualObject.availableObjects.index(of: object) else { continue }
            objectsViewController.selectedVirtualObjectRows.insert(index)
        }
    }
    
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        objectsViewController = nil
    }
}

// MARK: Measure

extension ViewController {
    
    @objc func handleTapGesture(sender: UITapGestureRecognizer) {
        guard measureSwitch.isOn else {
            showVirtualObjectSelectionViewController()
            return
        }
        
        if sender.state != .ended {
            return
        }
        guard let currentFrame = sceneView.session.currentFrame else {
            return
        }

        if let endNode = endNode {
            // Reset
            removeNodes()
            return
        }

        let planeHitTestResults = sceneView.hitTest(view.center, types: .existingPlaneUsingExtent)
        if let result = planeHitTestResults.first {
            let hitPosition = SCNVector3.positionFromTransform(result.worldTransform)
            let sphere = SCNSphere(radius: 0.005)
            sphere.firstMaterial?.diffuse.contents = UIColor.red
            sphere.firstMaterial?.lightingModel = .constant
            sphere.firstMaterial?.isDoubleSided = true
            let node = SCNNode(geometry: sphere)
            node.position = hitPosition
            sceneView.scene.rootNode.addChildNode(node)

            if let startNode = startNode {
                endNode = node
                let vector = startNode.position - node.position
                let formatter = NumberFormatter()
                formatter.numberStyle = .decimal
                formatter.roundingMode = .ceiling
                formatter.maximumFractionDigits = 2
                // Scene units map to meters in ARKit.
                distanceLabel.text = "Distance: " + formatter.string(from: NSNumber(value: vector.length()))! + " m"
            }
            else {
                startNode = node
            }
        }
        else {
            // Create a transform with a translation of 0.1 meters (10 cm) in front of the camera
            var translation = matrix_identity_float4x4
            translation.columns.3.z = -0.1
            // Add a node to the session
            let sphere = SCNSphere(radius: 0.005)
            sphere.firstMaterial?.diffuse.contents = UIColor.red
            sphere.firstMaterial?.lightingModel = .constant
            sphere.firstMaterial?.isDoubleSided = true
            let sphereNode = SCNNode(geometry: sphere)
            sphereNode.simdTransform = simd_mul(currentFrame.camera.transform, translation)
            sceneView.scene.rootNode.addChildNode(sphereNode)

            if let startNode = startNode {
                endNode = sphereNode
                self.distanceLabel.text = String(format: "%.2f", distance(startNode: startNode, endNode: sphereNode)) + "m"
            }
            else {
                startNode = sphereNode
            }
        }
    }
    
    func removeNodes() {
        startNode?.removeFromParentNode()
        self.startNode = nil
        endNode?.removeFromParentNode()
        self.endNode = nil
        distanceLabel.text = "Distance: ?"
    }
}
