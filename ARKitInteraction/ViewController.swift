/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/

import ARKit
import SceneKit
import UIKit

class ViewController: UIViewController {
    
    // MARK: IBOutlets
    
    @IBOutlet var sceneView: VirtualObjectARView!
    
    @IBOutlet weak var addObjectButton: UIButton!
    
    @IBOutlet weak var blurView: UIVisualEffectView!
    
    @IBOutlet weak var spinner: UIActivityIndicatorView!
    
    @IBOutlet weak var upperControlsView: UIView!

    @IBOutlet weak var measureSwitch: UISwitch!
    
    @IBOutlet weak var distanceLabel: UILabel!
    
    @IBOutlet weak var objDetectionCV: UIView!
    
    @IBOutlet weak var objDetectionSwitch: UISwitch!
    
    var trackingStateLabel = UILabel()
    
    var startNode: SCNNode?
    var endNode: SCNNode?
    
    var measureHandler = MeasureHandler()
    
    // MARK: - UI Elements
    
    let coachingOverlay = ARCoachingOverlayView()
    
    var focusSquare = FocusSquare()
    
    /// The view controller that displays the status and "restart experience" UI.
    lazy var statusViewController: StatusViewController = {
        return childViewControllers.lazy.compactMap({ $0 as? StatusViewController }).first!
    }()
    
    /// The view controller that displays the virtual object selection menu.
    var objectsViewController: VirtualObjectSelectionViewController?
    
    // MARK: - ARKit Configuration Properties
    
    /// A type which manages gesture manipulation of virtual content in the scene.
    lazy var virtualObjectInteraction = VirtualObjectInteraction(sceneView: sceneView, viewController: self)
    
    /// Coordinates the loading and unloading of reference nodes for virtual objects.
    let virtualObjectLoader = VirtualObjectLoader()
    
    /// Marks if the AR experience is available for restart.
    var isRestartAvailable = true
    
    /// A serial queue used to coordinate adding or removing nodes from the scene.
    let updateQueue = DispatchQueue(label: "com.example.apple-samplecode.arkitexample.serialSceneKitQueue")
    
    var screenCenter: CGPoint {
        let bounds = sceneView.bounds
        return CGPoint(x: bounds.midX, y: bounds.midY)
    }
    
    /// Convenience accessor for the session owned by ARSCNView.
    var session: ARSession {
        return sceneView.session
    }
    
    var objectDetectionVC: ObjectDetectionViewController? = nil
    
    // MARK: - View Controller Life Cycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
        sceneView.session.delegate = self
        
        // Set up coaching overlay.
        setupCoachingOverlay()

        // Set up scene content.
        sceneView.scene.rootNode.addChildNode(focusSquare)

        // Hook up status view controller callback(s).
        statusViewController.restartExperienceHandler = { [unowned self] in
            self.restartExperience()
        }
        
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(ViewController.handleTapGesture))
        // Set the delegate to ensure this gesture is only used when there are no virtual objects in the scene.
        tapGesture.delegate = self
        sceneView.addGestureRecognizer(tapGesture)
        
        // setup Measure View
        
        setUpMeasureView()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Prevent the screen from being dimmed to avoid interuppting the AR experience.
        UIApplication.shared.isIdleTimerDisabled = true

        // Start the `ARSession`.
        resetTracking()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        session.pause()
    }
    
    // MARK: Object Detection Config
    
    func setUpObjDetectionView() {
        objDetectionCV.isHidden = true
    }
    
    @IBAction func objDetectionValueChanged(_ sender: Any) {
        if objDetectionSwitch.isOn {
            sceneView.isHidden = true
            measureSwitch.isOn = false
            measureSwitchValueChanged(measureSwitch)
            session.pause()
            objectDetectionVC?.resizePreviewLayer()
            objectDetectionVC?.videoCapture.start()
            objDetectionCV.isHidden = false
            
        } else {
            objDetectionCV.isHidden = true
            objectDetectionVC?.videoCapture.stop()
            resetTracking()
            sceneView.isHidden = false
        }
    }
    
    // MARK: Measure View Config
    
    @IBAction func measureSwitchValueChanged(_ sender: Any) {
        guard let measureSwitch = sender as? UISwitch else {
            return
        }
        print(measureSwitch.isOn)
        if measureSwitch.isOn {
            virtualObjectInteraction.isMeasureModeOn = true
            measureHandler.delegate = self
            sceneView.delegate = measureHandler
            sceneView.session.delegate = measureHandler
            objectsViewController?.view.isHidden = true
            addObjectButton.isHidden = true
            setupFocusSquare()
            distanceLabel.isHidden = false
            trackingStateLabel.isHidden = false
            upperControlsView.isHidden = true
            focusSquare.hide()
        } else {
            measureFocusSquare.hide()
            self.removeNodes()
            virtualObjectInteraction.isMeasureModeOn = false
            measureHandler.delegate = nil
            sceneView.delegate = self
            sceneView.session.delegate = self
            objectsViewController?.view.isHidden = false
            addObjectButton.isHidden = false
            distanceLabel.isHidden = true
            trackingStateLabel.isHidden = true
            upperControlsView.isHidden = false
        }
    }
    
    func setUpMeasureView() {
//        sceneView.delegate = measureHandler
        // Show statistics such as fps and timing information
//        sceneView.showsStatistics = true

//        let tapGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(ViewController.handleTapGesture))
//        sceneView.addGestureRecognizer(tapGestureRecognizer)

//        distanceLabel.text = "Distance: ?"
//        distanceLabel.textColor = .red
//        distanceLabel.frame = CGRect(x: 5, y: 5, width: 150, height: 25)
//        view.addSubview(distanceLabel)

        trackingStateLabel.frame = CGRect(x: 5, y: 35, width: 300, height: 25)
        distanceLabel.isHidden = true
        trackingStateLabel.isHidden = true
        view.addSubview(trackingStateLabel)

//        setupFocusSquare()
    }
    
    // MARK: - Session management
    
    /// Creates a new AR configuration to run on the `session`.
    func resetTracking() {
        virtualObjectInteraction.selectedObject = nil
        
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal, .vertical]
        if #available(iOS 12.0, *) {
            configuration.environmentTexturing = .automatic
        }
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])

        statusViewController.scheduleMessage("FIND A SURFACE TO PLACE AN OBJECT", inSeconds: 7.5, messageType: .planeEstimation)
    }

    // MARK: - Focus Square

    func updateFocusSquare(isObjectVisible: Bool) {
        if isObjectVisible || coachingOverlay.isActive {
            focusSquare.hide()
        } else {
            focusSquare.unhide()
            statusViewController.scheduleMessage("TRY MOVING LEFT OR RIGHT", inSeconds: 5.0, messageType: .focusSquare)
        }
        
        // Perform ray casting only when ARKit tracking is in a good state.
        if let camera = session.currentFrame?.camera, case .normal = camera.trackingState,
            let query = getRaycastQuery(),
            let result = castRay(for: query).first {
            
            updateQueue.async {
                self.sceneView.scene.rootNode.addChildNode(self.focusSquare)
                self.focusSquare.state = .detecting(raycastResult: result, camera: camera)
            }
            if !coachingOverlay.isActive {
                addObjectButton.isHidden = false
            }
            statusViewController.cancelScheduledMessage(for: .focusSquare)
        } else {
            updateQueue.async {
                self.focusSquare.state = .initializing
                self.sceneView.pointOfView?.addChildNode(self.focusSquare)
            }
            addObjectButton.isHidden = true
        }
    }
    
    // - Tag: CastRayForFocusSquarePosition
    func castRay(for query: ARRaycastQuery) -> [ARRaycastResult] {
        return session.raycast(query)
    }

    // - Tag: GetRaycastQuery
    func getRaycastQuery() -> ARRaycastQuery? {
        return sceneView.raycastQuery(from: screenCenter, allowing: .estimatedPlane, alignment: .any)
    }
    
    // MARK: - Error handling
    
    func displayErrorMessage(title: String, message: String) {
        // Blur the background.
        blurView.isHidden = false
        
        // Present an alert informing about the error that has occurred.
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        let restartAction = UIAlertAction(title: "Restart Session", style: .default) { _ in
            alertController.dismiss(animated: true, completion: nil)
            self.blurView.isHidden = true
            self.resetTracking()
        }
        alertController.addAction(restartAction)
        present(alertController, animated: true, completion: nil)
    }

    func distance(startNode: SCNNode, endNode: SCNNode) -> Float {
        let vector = SCNVector3Make(startNode.position.x - endNode.position.x, startNode.position.y - endNode.position.y, startNode.position.z - endNode.position.z)
        // Scene units map to meters in ARKit.
        return sqrtf(vector.x * vector.x + vector.y * vector.y + vector.z * vector.z)
    }

    var dragOnInfinitePlanesEnabled = false

    // MARK: - Focus Square

    var measureFocusSquare = MeasureFocusSquare()

    func setupFocusSquare() {
        measureFocusSquare.unhide()
        measureFocusSquare.removeFromParentNode()
        sceneView.scene.rootNode.addChildNode(measureFocusSquare)
    }

}

extension ViewController {

    // Code from Apple PlacingObjects demo: https://developer.apple.com/sample-code/wwdc/2017/PlacingObjects.zip

    func worldPositionFromScreenPosition(_ position: CGPoint,
                                         objectPos: SCNVector3?,
                                         infinitePlane: Bool = false) -> (position: SCNVector3?, planeAnchor: ARPlaneAnchor?, hitAPlane: Bool) {

        // -------------------------------------------------------------------------------
        // 1. Always do a hit test against exisiting plane anchors first.
        //    (If any such anchors exist & only within their extents.)

        let planeHitTestResults = sceneView.hitTest(position, types: .existingPlaneUsingExtent)
        if let result = planeHitTestResults.first {

            let planeHitTestPosition = SCNVector3.positionFromTransform(result.worldTransform)
            let planeAnchor = result.anchor

            // Return immediately - this is the best possible outcome.
            return (planeHitTestPosition, planeAnchor as? ARPlaneAnchor, true)
        }

        // -------------------------------------------------------------------------------
        // 2. Collect more information about the environment by hit testing against
        //    the feature point cloud, but do not return the result yet.

        var featureHitTestPosition: SCNVector3?
        var highQualityFeatureHitTestResult = false

        let highQualityfeatureHitTestResults = sceneView.hitTestWithFeatures(position, coneOpeningAngleInDegrees: 18, minDistance: 0.2, maxDistance: 2.0)

        if !highQualityfeatureHitTestResults.isEmpty {
            let result = highQualityfeatureHitTestResults[0]
            featureHitTestPosition = result.position
            highQualityFeatureHitTestResult = true
        }

        // -------------------------------------------------------------------------------
        // 3. If desired or necessary (no good feature hit test result): Hit test
        //    against an infinite, horizontal plane (ignoring the real world).

        if (infinitePlane && dragOnInfinitePlanesEnabled) || !highQualityFeatureHitTestResult {

            let pointOnPlane = objectPos ?? SCNVector3Zero

            let pointOnInfinitePlane = sceneView.hitTestWithInfiniteHorizontalPlane(position, pointOnPlane)
            if pointOnInfinitePlane != nil {
                return (pointOnInfinitePlane, nil, true)
            }
        }

        // -------------------------------------------------------------------------------
        // 4. If available, return the result of the hit test against high quality
        //    features if the hit tests against infinite planes were skipped or no
        //    infinite plane was hit.

        if highQualityFeatureHitTestResult {
            return (featureHitTestPosition, nil, false)
        }

        // -------------------------------------------------------------------------------
        // 5. As a last resort, perform a second, unfiltered hit test against features.
        //    If there are no features in the scene, the result returned here will be nil.

        let unfilteredFeatureHitTestResults = sceneView.hitTestWithFeatures(position)
        if !unfilteredFeatureHitTestResults.isEmpty {
            let result = unfilteredFeatureHitTestResults[0]
            return (result.position, nil, false)
        }

        return (nil, nil, false)
    }

}

extension ViewController: MeasureHandlerDelegate {
    
    func updateFocusSquare() {
        let (worldPosition, planeAnchor, _) = worldPositionFromScreenPosition(view.center, objectPos: focusSquare.position)
        if let worldPosition = worldPosition {
            measureFocusSquare.update(for: worldPosition, planeAnchor: planeAnchor, camera: sceneView.session.currentFrame?.camera)
        }
    }
    
    func measureSession(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        switch camera.trackingState {
        case .notAvailable:
            trackingStateLabel.text = "Tracking not available"
            trackingStateLabel.textColor = .red
        case .normal:
            trackingStateLabel.text = "Tracking normal"
            trackingStateLabel.textColor = .green
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                trackingStateLabel.text = "Tracking limited: excessive motion"
            case .insufficientFeatures:
                trackingStateLabel.text = "Tracking limited: insufficient features"
            case .initializing:
                trackingStateLabel.text = "Tracking limited: initializing"
            default:
                break
            }
            trackingStateLabel.textColor = .yellow
        }
    }
    
}
