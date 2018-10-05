//
//  CSController.swift
//  Capture
//
//  Created by Jean on 9/7/15.
//  Copyright © 2015 mobileuse. All rights reserved.
//

import UIKit
import AVFoundation
import Photos

enum CaptureSessionError : Error {
    enum InputError : Error {
        case cannotAddToSession
        case cannotConnect
        case initFailed(Error?)
    }
    enum OutputError : Error {
        case cannotAddToSession
        case cannotConnect
    }
    case noCameraForPosition
    case cameraInputError(InputError)
    case audioInputError(InputError)
    case cameraAccessDenied
    case photoLibraryAccessDenied
    case photoOutputError(OutputError)
    case videoOutputError(OutputError)
}

// MARK: Delegate Protocol

protocol CaptureSessionControllerDelegate {
    func captureSessionControllerError(error: Error)
    func captureSessionControllerNotification(notification:CSNotification)
}

// change type
enum CSChange {
    enum ExposureType {
        case iso(Float), targetOffset(Float), duration(CMTime)
        case bias(Float)
        
        case minISO(Float), maxISO(Float)
        case minDuration(CMTime), maxDuration(CMTime)
    }
    case lensPosition(Float)
    case exposure(ExposureType)
    case whiteBalanceGains(AVCaptureDevice.WhiteBalanceGains)
    case zoomFactor(CGFloat)
    case aspectRatio(CSAspectRatio)
    
    
    case focusMode(AVCaptureDevice.FocusMode)
    case exposureMode(AVCaptureDevice.ExposureMode)
    case whiteBalanceMode(AVCaptureDevice.WhiteBalanceMode)
    case aspectRatioMode(CSAspectRatioMode)
}

// value set type
enum CSSet {
    enum ExposureType {
        case bias(Float)
        case durationAndISO(CMTime, Float)
    }
    case lensPosition(Float)
    case exposure(ExposureType)
    case whiteBalanceGains(AVCaptureDevice.WhiteBalanceGains)
    case zoomFactor(CGFloat), zoomFactorRamp(CGFloat, Float)
    case aspectRatio(CSAspectRatio)
    
    
    case focusMode(AVCaptureDevice.FocusMode)
    case exposureMode(AVCaptureDevice.ExposureMode)
    case whiteBalanceMode(AVCaptureDevice.WhiteBalanceMode)
    case aspectRatioMode(CSAspectRatioMode)
}

// notification type
enum CSNotification {
    case capturingPhoto(Bool)
    case photoSaved
    case subjectAreaChange
    case sessionRunning(Bool)
}

typealias CSAspectRatio = CGFloat
func CSAspectRatioMake(_ width: CGFloat, _ height: CGFloat) -> CSAspectRatio {
    return width / height
}

enum CSAspectRatioMode: Int {
    case lock, fullscreen, sensor
}

class CaptureSession: NSObject {
    
    private var _notifObservers: [ String : AnyObject? ] = [ : ]
    typealias KVOContext = UInt8
    private var _context: [ String : KVOContext ] = [ : ]
    
    let session: AVCaptureSession
    let sessionQueue: DispatchQueue
    let previewView: PreviewView
    var camera: AVCaptureDevice!
    var cameraInput: AVCaptureDeviceInput!
    var photoOutput: AVCaptureStillImageOutput!
    var aspectRatio = CSAspectRatioMake(16,9) {
        didSet{
            if (aspectRatioMode == .lock) {
                let orientation = UIApplication.shared.statusBarOrientation
                let inverse = 1 / aspectRatio
                previewView.aspectRatio = (orientation == .portrait) ? inverse : aspectRatio
            } else {
                previewView.aspectRatio = aspectRatio
            }
            notify(change: .aspectRatio(aspectRatio) )
            
        }
    }
    var aspectRatioMode: CSAspectRatioMode = .fullscreen {
        didSet{
            updateAspectRatio()
            notify(change: .aspectRatioMode(aspectRatioMode) )
        }
    }
    func updateAspectRatio() {
        guard previewView.previewLayer.connection != nil else { return }
        switch aspectRatioMode {
        case .lock:
            let aspectRatio = self.aspectRatio
            self.aspectRatio = aspectRatio
        case .fullscreen:
            let orientation = UIApplication.shared.statusBarOrientation
            let width = (orientation == .portrait) ? UIScreen.main.bounds.height : UIScreen.main.bounds.width
            let height = (orientation == .portrait) ? UIScreen.main.bounds.width : UIScreen.main.bounds.height
            self.aspectRatio = CSAspectRatioMake(width, height)
        case .sensor:
            let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            let size = previewView.previewLayer.layerRectConverted(fromMetadataOutputRect: unitRect).size
            self.aspectRatio = CSAspectRatioMake(size.width, size.height)
        }
    }
    var volumeButtonHandler = JPSVolumeButtonHandler()
    
    var delegate: CaptureSessionControllerDelegate?
    
    struct VOBlocks {
        
        typealias LensPositionBlock = (Float) -> ()
        typealias ISOBlock = (Float) -> ()
        typealias ExposureDurationBlock = (CMTime) -> ()
        typealias TargetOffsetBlock = (Float) -> ()
        typealias TargetBiasBlock = (Float) -> ()
        typealias WhiteBalanceGainsBlock = (AVCaptureDevice.WhiteBalanceGains) -> ()
        typealias ZoomFactorBlock = (CGFloat) -> ()
        
        typealias FocusModeBlock = (AVCaptureDevice.FocusMode) -> ()
        typealias ExposureModeBlock = (AVCaptureDevice.ExposureMode) -> ()
        typealias WhiteBalanceModeBlock = (AVCaptureDevice.WhiteBalanceMode) -> ()
        typealias AspectRatioModeBlock = (CSAspectRatioMode) -> ()
        
        typealias AspectRatioBlock = (CSAspectRatio) -> ()
        
        var lensPosition        = [ String : LensPositionBlock ]()
        var iso                 = [ String : ISOBlock ]()
        var exposureDuration    = [ String : ExposureDurationBlock ]()
        var targetOffset        = [ String : TargetOffsetBlock ]()
        var targetBias          = [ String : TargetOffsetBlock ]()
        var whiteBalance        = [ String : WhiteBalanceGainsBlock ]()
        var zoomFactor          = [ String : ZoomFactorBlock ]()
        
        var focusMode           = [ String : FocusModeBlock ]()
        var exposureMode        = [ String : ExposureModeBlock ]()
        var whiteBalanceMode    = [ String : WhiteBalanceModeBlock ]()
        var aspectRatioMode     = [ String : AspectRatioModeBlock ]()
        
        var aspectRatio         = [ String : AspectRatioBlock ]()
        
    }
    var voBlocks = VOBlocks()
    var observers = [NSKeyValueObservation]()
    
    override init() {
        
        session = AVCaptureSession()
        session.sessionPreset = AVCaptureSession.Preset.photo
        
        sessionQueue = DispatchQueue(label: "com.manual-camera.session")
        
        previewView = PreviewView(session: session)
        previewView.aspectRatio = aspectRatio
        
        super.init()
        
        unowned let me = self
        volumeButtonHandler.downBlock = { me.captureStillPhoto() }
        
        requestCameraAccess {
            self.startCamera()
        }
        requestPhotoLibraryAccess {
            // success
        }
    }
    
    private func requestCameraAccess(completionHandler:@escaping ()->Void) {
        
        AVCaptureDevice.requestAccess( for: AVMediaType.video ) { granted in
            if granted {
                completionHandler()
            } else {
                self.notify(error: CaptureSessionError.cameraAccessDenied)
            }
        }
    }
    
    private func requestPhotoLibraryAccess(completionHandler:@escaping ()->Void) {
        PHPhotoLibrary.requestAuthorization() { status in
            if status == .authorized {
                completionHandler()
            } else {
                self.notify(error: CaptureSessionError.photoLibraryAccessDenied)
            }
        }
    }
    
    func startCamera() {
        
        func addDevicesIfNeeded(){
            
            func addCameraFromPosition(position:AVCaptureDevice.Position) throws {
                if #available(iOS 10.0, *), let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)  {
                    camera =  device
                    return
                } else if let device = AVCaptureDevice.`default`(for: .video), device.position == position {
                    camera =  device
                    return
                } else {
                    let devices = AVCaptureDevice.devices(for: .video).filter() { $0.position == position }
                    if !devices.isEmpty {
                        camera =  devices[0]
                        return
                    }
                }
                throw CaptureSessionError.noCameraForPosition
            }
            
            func addInputFromCamera(camera:AVCaptureDevice) throws {
                do {
                    cameraInput = try AVCaptureDeviceInput(device: camera)
                }
                catch {
                    throw CaptureSessionError.cameraInputError(.initFailed(error))
                }
                guard session.canAddInput(cameraInput) else {
                    throw CaptureSessionError.cameraInputError(.cannotAddToSession)
                }
                session.addInput(cameraInput)
                guard let connection = previewView.previewLayer.connection else {
                    throw CaptureSessionError.cameraInputError(.cannotConnect)
                }
                connection.videoOrientation = .landscapeRight
                connection.preferredVideoStabilizationMode = .auto
            }
            
            func addPhotoOutput() throws {
                photoOutput = AVCaptureStillImageOutput()
                guard session.canAddOutput(photoOutput) else {
                    throw CaptureSessionError.photoOutputError(.cannotAddToSession)
                }
                photoOutput.isHighResolutionStillImageOutputEnabled = true
                session.addOutput(photoOutput)
            }
            
            do {
                session.beginConfiguration()
                if camera == nil {
                    try addCameraFromPosition(position: .back)
                }
                if cameraInput == nil {
                    try addInputFromCamera(camera: camera)
                }
                if photoOutput == nil {
                    try addPhotoOutput()
                }
                session.commitConfiguration()
            } catch {
                self.notify(error: error)
            }
        }
        
        func startRunningSession() {
            sessionQueue.async() {
                self.addObservers()
                self.session.startRunning()
            }
        }
        
        addDevicesIfNeeded()
        startRunningSession()
    }
    
    // MARK: Notify
    
    private func notify(error: Error) {
        DispatchQueue.main.async { [unowned self] in
            self.delegate?.captureSessionControllerError(error: error)
            print(error)
        }
    }
    
    private func notify(notification: CSNotification) {
        DispatchQueue.main.async { [unowned self] in
            self.delegate?.captureSessionControllerNotification(notification: notification)
        }
    }
    
    private func notify(change: CSChange) {
        switch change {
        case .lensPosition(let v): self.voBlocks.lensPosition.forEach { $1(v) }
        case .exposure(.iso(let v)): self.voBlocks.iso.forEach { $1(v) }
        case .exposure(.duration(let v)): self.voBlocks.exposureDuration.forEach { $1(v) }
        case .exposure(.targetOffset(let v)): self.voBlocks.targetOffset.forEach { $1(v) }
        case .exposure(.bias(let v)): self.voBlocks.targetBias.forEach { $1(v) }
        case .whiteBalanceGains(let v): self.voBlocks.whiteBalance.forEach { $1(v) }
        case .zoomFactor(let v): self.voBlocks.zoomFactor.forEach { $1(v) }
            
        case .focusMode(let v): self.voBlocks.focusMode.forEach { $1(v) }
        case .exposureMode(let v): self.voBlocks.exposureMode.forEach { $1(v) }
        case .whiteBalanceMode(let v): self.voBlocks.whiteBalanceMode.forEach { $1(v) }
        case .aspectRatioMode(let v): self.voBlocks.aspectRatioMode.forEach { $1(v) }
            
        case .aspectRatio(let v): self.voBlocks.aspectRatio.forEach { $1(v) }
        default: break
        }
    }
    
    private func addObservers() {
        self.observers = [
            photoOutput.observe(\AVCaptureStillImageOutput.isCapturingStillImage, options: [.initial], changeHandler: {
                [unowned self] photoOutput, _ in
                self.notify(notification: .capturingPhoto(photoOutput.isCapturingStillImage) )
            }),
            camera.observe(\AVCaptureDevice.focusMode, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .focusMode(camera.focusMode) )
            }),
            camera.observe(\AVCaptureDevice.exposureMode, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .exposureMode(camera.exposureMode) )
            }),
            camera.observe(\AVCaptureDevice.whiteBalanceMode, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .whiteBalanceMode(camera.whiteBalanceMode) )
            }),
            camera.observe(\AVCaptureDevice.iso, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .exposure(.iso(camera.iso)) )
            }),
            camera.observe(\AVCaptureDevice.exposureTargetOffset, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .exposure(.targetOffset(camera.exposureTargetOffset)) )
            }),
            camera.observe(\AVCaptureDevice.exposureDuration, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .exposure(.duration(camera.exposureDuration)) )
            }),
            camera.observe(\AVCaptureDevice.deviceWhiteBalanceGains, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .whiteBalanceGains(camera.deviceWhiteBalanceGains) )
            }),
            camera.observe(\AVCaptureDevice.lensPosition, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .lensPosition(camera.lensPosition) )
            }),
        ]
        
        _notifObservers["RuntimeError"] = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionRuntimeError,
            object: sessionQueue,
            queue: OperationQueue.main,
            using: { [unowned self] (_) in
                self.sessionQueue.async() {
                    self.session.startRunning()
                }
            }
        )
        
        _notifObservers["SubjectAreaChange"] = NotificationCenter.default.addObserver(
            forName: .AVCaptureDeviceSubjectAreaDidChange,
            object: camera,
            queue: OperationQueue.main,
            using: { [unowned self] (_) in
                self.delegate?.captureSessionControllerNotification(notification: .subjectAreaChange)
            }
        )
        
        _notifObservers["SessionStarted"] = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStartRunning,
            object: session, queue: OperationQueue.main,
            using: { [unowned self] (_) in
                self.delegate?.captureSessionControllerNotification(notification: .sessionRunning(true) )
            }
        )
        
        _notifObservers["SessionStopped"] = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStopRunning,
            object: session,
            queue: OperationQueue.main,
            using: { [unowned self] (_) in
                self.delegate?.captureSessionControllerNotification(notification: .sessionRunning(false) )
            }
        )
        
    }
    
    func set(_ set:CSSet){
//        guard !isDemoMode else { return }
        let cameraConfig = { (config: () -> Void) -> Void in
            do {
                try self.camera.lockForConfiguration()
                config()
                self.camera.unlockForConfiguration()
            }
            catch {
                print(error)
            }
        }
        
        switch set {
        case .focusMode( let focusMode ):
            cameraConfig(){
                self.camera.focusMode = focusMode
            }
        case .exposureMode( let exposureMode ):
            cameraConfig(){
                self.camera.exposureMode = exposureMode
            }
        case .whiteBalanceMode( let whiteBalanceMode ):
            cameraConfig(){
                self.camera.whiteBalanceMode = whiteBalanceMode
            }
        case .exposure( .durationAndISO( let duration , let iso ) ):
            cameraConfig(){
                self.camera.setExposureModeCustom(duration: duration, iso: iso, completionHandler: nil)
            }
        case .exposure( .bias( let bias ) ):
            cameraConfig(){
                self.camera.setExposureTargetBias( bias, completionHandler: nil )
            }
        case .lensPosition( let lensPosition ):
            cameraConfig(){
                self.camera.setFocusModeLocked( lensPosition: lensPosition, completionHandler: nil )
            }
        case .whiteBalanceGains( let wbgains ):
            cameraConfig(){
                self.camera.setWhiteBalanceModeLocked( with: wbgains, completionHandler: nil )
            }
        case .zoomFactor(let zFactor):
            cameraConfig(){
                self.camera.videoZoomFactor = zFactor
            }
        case .zoomFactorRamp(let zFactor, let rate):
            cameraConfig(){
                self.camera.ramp(toVideoZoomFactor: zFactor, withRate: rate)
            }
        case .aspectRatio(let aspectRatio):
            self.aspectRatioMode = .lock
            self.aspectRatio = aspectRatio
        case .aspectRatioMode(let aspectRatioMode):
            self.aspectRatioMode = aspectRatioMode
        }
    }
    
    @objc func captureStillPhoto() {
        let orientation = UIApplication.shared.statusBarOrientation
        
        sessionQueue.async(){
            func captureError(errorText:String) {
                DispatchQueue.main.async {
                    UIAlertView(title: "Capture Error", message: errorText, delegate: nil, cancelButtonTitle: "Dismiss").show()
                }
            }
            
            // Update the orientation on the still image output video connection before capturing.
            guard let connection = self.photoOutput.connection(with: AVMediaType.video) else {
                captureError(errorText: "Output connection was bad. Try retaking photo.")
                return
            }
            connection.videoOrientation = self.previewView.previewLayer.connection?.videoOrientation ?? .landscapeRight
            
            self.photoOutput.captureStillImageAsynchronously(from: connection){
                (imageSampleBuffer, error) in
                guard let imageSampleBuffer = imageSampleBuffer else{
                    captureError(errorText: "Couldn't retrieve sample buffer. Try retaking photo.")
                    return
                }
                guard let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageSampleBuffer) else {
                    captureError(errorText: "Couldn't get image data. Try retaking photo.")
                    return
                }
                guard let image: UIImage = UIImage(data: imageData) else {
                    captureError(errorText: "Couldn't create image from data. Try retaking photo.")
                    return
                }
                
                let scaled = (
                    width: min( image.size.height * self.aspectRatio, image.size.width),
                    height: min( image.size.width / self.aspectRatio, image.size.height)
                )
                let cropRect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height).insetBy(
                    dx: (image.size.width - scaled.width) / 2 , // clipped width
                    dy: (image.size.height - scaled.height) / 2 // clipped height
                )
                guard let cgImage = image.cgImage else {
                    captureError(errorText: "Couldn't turn image into CGImage. Try retaking photo.")
                    return
                }
                guard let croppedImage = cgImage.cropping(to: cropRect) else {
                    captureError(errorText: "Couldn't crop image to apropriate size. Try retaking photo.")
                    return
                }
                var imageOrientation: UIImage.Orientation {
                    switch orientation {
                    case .landscapeRight: return .up
                    case .portrait: return.right
                    case .landscapeLeft: return .down
                    case .portraitUpsideDown: return .left
                    case .unknown: return .up
                    }
                }
                let rotImage = UIImage(cgImage: croppedImage, scale: 1.0, orientation: imageOrientation)
                
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: rotImage)
                }, completionHandler: { [unowned self] success, error in
                    if success {
                        self.notify(notification: .photoSaved)
                    } else if let error = error {
                        self.notify(error: error)
                        captureError(errorText: "Couldn't save photo.\n Try going to Settings > Privacy > Photos\n Then switch \(kAppName) to On")
                    } else {
                        captureError(errorText: "Couldn't save photo.\n Try going to Settings > Privacy > Photos\n Then switch \(kAppName) to On")
                    }
                })
            }
        }
        
    }
    
    
    // MARK: Utilities
    
    
    func _normalizeGains(_ g:AVCaptureDevice.WhiteBalanceGains) -> AVCaptureDevice.WhiteBalanceGains {
        var g = g
        let maxGain = camera.maxWhiteBalanceGain - 0.001
        g.redGain = max( 1.0, g.redGain )
        
        g.greenGain = max( 1.0, g.greenGain )
        g.blueGain = max( 1.0, g.blueGain )
        g.redGain = min( maxGain, g.redGain )
        g.greenGain = min( maxGain, g.greenGain )
        g.blueGain = min( maxGain, g.blueGain )
        return g
    }
    
    
    
    /// previous tint and temp
    
    private var _ptt:AVCaptureDevice.WhiteBalanceTemperatureAndTintValues? = nil
    
    func _normalizeGainsForTemperatureAndTint(_ tt:AVCaptureDevice.WhiteBalanceTemperatureAndTintValues) -> AVCaptureDevice.WhiteBalanceGains{
        var g = camera.deviceWhiteBalanceGains(for: tt)
        if !_gainsInRange(gains: g){
            if _ptt != nil {
                let dTemp = tt.temperature - _ptt!.temperature
                let dTint = tt.tint - _ptt!.tint
                var eTint = round(tt.tint)
                var eTemperature = round(tt.temperature)
                var i = 0
                var eGains: AVCaptureDevice.WhiteBalanceGains = camera.deviceWhiteBalanceGains(for: tt)
                
                if abs(dTemp) > abs(dTint) {
                    while !_gainsInRange(gains: eGains) {
                        let nTT = camera.temperatureAndTintValues(for: _normalizeGains(eGains))
                        let eTintNew = round(nTT.tint)
                        let eTemperatureNew = round(nTT.temperature)
                        //prioritize
                        if eTint != eTintNew {
                            eTint = eTintNew
                        }
                        else if eTemperature != eTemperatureNew {
                            eTemperature = eTemperatureNew
                        }
                        if i > 3 || (eTint == eTintNew && eTemperature == eTemperatureNew) {
                            eGains = _normalizeGains(eGains)
                        }else{
                            eGains = camera.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: eTemperature, tint: eTint))
                        }
                        i += 1
                    }
                    g = eGains
                }else if abs(dTemp) < abs(dTint) {
                    while !_gainsInRange(gains: eGains) {
                        let nTT = camera.temperatureAndTintValues(for: _normalizeGains(eGains))
                        let eTintNew = round(nTT.tint)
                        let eTemperatureNew = round(nTT.temperature)
                        if eTemperature != eTemperatureNew {
                            eTemperature = eTemperatureNew
                        } else if eTint != eTintNew {
                            eTint = eTintNew
                        }
                        if i > 3 || (eTint == eTintNew && eTemperature == eTemperatureNew) {
                            eGains = _normalizeGains(eGains)
                        } else {
                            eGains = camera.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: eTemperature, tint: eTint))
                        }
                        i += 1
                    }
                    g = eGains
                }
            }
        }
        _ptt = tt
        return _normalizeGains(g)
    }
    
    func _gainsInRange(gains:AVCaptureDevice.WhiteBalanceGains) -> Bool {
        let maxGain = camera.maxWhiteBalanceGain
        let r = (1.0 <= gains.redGain && gains.redGain <= maxGain)
        let g = (1.0 <= gains.greenGain && gains.greenGain <= maxGain)
        let b = (1.0 <= gains.blueGain && gains.blueGain <= maxGain)
        return r && g && b
    }
    
}
