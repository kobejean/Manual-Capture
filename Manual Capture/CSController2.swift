//
//  CSController.swift
//  Capture
//
//  Created by Jean on 9/7/15.
//  Copyright © 2015 mobileuse. All rights reserved.
//

import UIKit
import AVFoundation
import AssetsLibrary

class CSController2: NSObject {
    
    private var _notifObservers: [ String : AnyObject? ] = [ : ]
    typealias KVOContext = UInt8
    private var _context: [ String : KVOContext ] = [ : ]
    
    let session: AVCaptureSession
    let sessionQueue: DispatchQueue
    let previewView: CapturePreviewView
    var camera: AVCaptureDevice!
    var cameraInput: AVCaptureDeviceInput!
    var photoOutput: AVCaptureStillImageOutput!
    
    var aspectRatio = CSAspectRatioMake(16,9) {
        didSet{
            
            //previewView.aspectRatio = aspectRatio
            notify(change: .AspectRatio(aspectRatio) )
            
        }
    }
    var volumeButtonHandler = JPSVolumeButtonHandler()
    
    var delegate: CSControllerDelegate?
    
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
        
        var aspectRatio         = [ String : AspectRatioBlock ]()
        
    }
    var voBlocks = VOBlocks()
    var observers = [NSKeyValueObservation]()
    
    override init() {
        
        session = AVCaptureSession()
        session.sessionPreset = AVCaptureSession.Preset.photo
        
        sessionQueue = DispatchQueue(label: "com.manual-camera.session")
        
        previewView = CapturePreviewView(session: session)
        previewView.aspectRatio = aspectRatio
        
        super.init()
        
        unowned let me = self
        volumeButtonHandler.action = { me.captureStillPhoto() }
        
        
        requestCameraAccess(){
            self.startCamera()
        }
    }
    
    private func requestCameraAccess(completionHandler:@escaping ()->Void) {
        
        AVCaptureDevice.requestAccess( for: AVMediaType.video ) {
            (granted) in
            if granted {
                completionHandler()
            }else{
                self.notify(error: SessionError.CameraAccessDenied)
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
                throw SessionError.NoCameraForPosition
            }
            
            func addInputFromCamera(camera:AVCaptureDevice) throws {
                do {
                    cameraInput = try AVCaptureDeviceInput(device: camera)
                }
                catch {
                    throw SessionError.CameraInputError(.InitFailed(error))
                }
                guard session.canAddInput(cameraInput) else {
                    throw SessionError.CameraInputError(.CannotAddToSession)
                }
                session.addInput(cameraInput)
                guard let connection = previewView.previewLayer.connection else {
                    throw SessionError.CameraInputError(.CannotConnect)
                }
                connection.videoOrientation = .landscapeRight
                connection.preferredVideoStabilizationMode = .auto
            }
            
            func addPhotoOutput() throws {
                photoOutput = AVCaptureStillImageOutput()
                guard session.canAddOutput(photoOutput) else {
                    throw SessionError.PhotoOutputError(.CannotAddToSession)
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
            self.delegate?.sessionControllerError(error: error)
            print(error)
        }
    }
    
    private func notify(notification: CSNotification) {
        DispatchQueue.main.async { [unowned self] in
            self.delegate?.sessionControllerNotification(notification: notification)
        }
    }
    
    private func notify(change: CSChange) {
        switch change {
        case .LensPosition(let v): self.voBlocks.lensPosition.forEach { $1(v) }
        case .Exposure(.ISO(let v)): self.voBlocks.iso.forEach { $1(v) }
        case .Exposure(.Duration(let v)): self.voBlocks.exposureDuration.forEach { $1(v) }
        case .Exposure(.TargetOffset(let v)): self.voBlocks.targetOffset.forEach { $1(v) }
        case .Exposure(.Bias(let v)): self.voBlocks.targetBias.forEach { $1(v) }
        case .WhiteBalanceGains(let v): self.voBlocks.whiteBalance.forEach { $1(v) }
        case .ZoomFactor(let v): self.voBlocks.zoomFactor.forEach { $1(v) }
            
        case .FocusMode(let v): self.voBlocks.focusMode.forEach { $1(v) }
        case .ExposureMode(let v): self.voBlocks.exposureMode.forEach { $1(v) }
        case .WhiteBalanceMode(let v): self.voBlocks.whiteBalanceMode.forEach { $1(v) }
            
        case .AspectRatio(let v): self.voBlocks.aspectRatio.forEach { $1(v) }
        default: break
        }
    }
    
    private func addObservers() {
        self.observers = [
            photoOutput.observe(\AVCaptureStillImageOutput.isCapturingStillImage, options: [.initial], changeHandler: {
                [unowned self] photoOutput, _ in
                self.notify(notification: .CapturingPhoto(photoOutput.isCapturingStillImage) )
            }),
            camera.observe(\AVCaptureDevice.focusMode, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .FocusMode(camera.focusMode) )
            }),
            camera.observe(\AVCaptureDevice.exposureMode, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .ExposureMode(camera.exposureMode) )
            }),
            camera.observe(\AVCaptureDevice.whiteBalanceMode, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .WhiteBalanceMode(camera.whiteBalanceMode) )
            }),
            camera.observe(\AVCaptureDevice.iso, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .Exposure(.ISO(camera.iso)) )
            }),
            camera.observe(\AVCaptureDevice.exposureTargetOffset, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .Exposure(.TargetOffset(camera.exposureTargetOffset)) )
            }),
            camera.observe(\AVCaptureDevice.exposureDuration, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .Exposure(.Duration(camera.exposureDuration)) )
            }),
            camera.observe(\AVCaptureDevice.deviceWhiteBalanceGains, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .WhiteBalanceGains( camera.deviceWhiteBalanceGains ) )
            }),
            camera.observe(\AVCaptureDevice.lensPosition, options: [.initial], changeHandler: {
                [unowned self] camera, _ in
                self.notify(change: .LensPosition(camera.lensPosition) )
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
                self.delegate?.sessionControllerNotification(notification: .SubjectAreaChange)
            }
        )
        
        _notifObservers["SessionStarted"] = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStartRunning,
            object: session, queue: OperationQueue.main,
            using: { [unowned self] (_) in
                self.delegate?.sessionControllerNotification(notification: .SessionRunning(true) )
            }
        )
        
        _notifObservers["SessionStopped"] = NotificationCenter.default.addObserver(
            forName: .AVCaptureSessionDidStopRunning,
            object: session,
            queue: OperationQueue.main,
            using: { [unowned self] (_) in
                self.delegate?.sessionControllerNotification(notification: .SessionRunning(false) )
            }
        )
        
    }
    
    func set(set:CSSet){
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
        case .FocusMode( let focusMode ):
            cameraConfig(){
                self.camera.focusMode = focusMode
            }
        case .ExposureMode( let exposureMode ):
            cameraConfig(){
                self.camera.exposureMode = exposureMode
            }
        case .WhiteBalanceMode( let whiteBalanceMode ):
            cameraConfig(){
                self.camera.whiteBalanceMode = whiteBalanceMode
            }
        case .Exposure( .DurationAndISO( let duration , let ISO ) ):
            cameraConfig(){
                self.camera.setExposureModeCustom(duration: duration, iso: ISO, completionHandler: nil)
            }
        case .Exposure( .Bias( let bias ) ):
            cameraConfig(){
                self.camera.setExposureTargetBias( bias, completionHandler: nil )
            }
        case .LensPosition( let lensPosition ):
            cameraConfig(){
                self.camera.setFocusModeLocked( lensPosition: lensPosition, completionHandler: nil )
            }
        case .WhiteBalanceGains( let wbgains ):
            cameraConfig(){
                self.camera.setWhiteBalanceModeLocked( with: wbgains, completionHandler: nil )
            }
        case .ZoomFactor(let zFactor):
            cameraConfig(){
                self.camera.videoZoomFactor = zFactor
            }
        case .ZoomFactorRamp(let zFactor, let rate):
            cameraConfig(){
                self.camera.ramp(toVideoZoomFactor: zFactor, withRate: rate)
            }
        case .AspectRatio(let aspectRatio):
            self.aspectRatio = aspectRatio
        case .AspectRatioMode( _): break
        }
    }
    
    func captureStillPhoto() {
        
        sessionQueue.async(){
            
            func captureError(errorText:String) {
                
                UIAlertView(title: "Capture Error", message: errorText, delegate: nil, cancelButtonTitle: "Dismiss").show()
                
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
                var cropRect = CGRect(x: 0, y: 0, width: image.size.width, height: image.size.height).insetBy(
                    dx: (image.size.width - scaled.width) / 2 , // clipped width
                    dy: (image.size.height - scaled.height) / 2 // clipped height
                )
                
                var cropTransForm: CGAffineTransform {
                    func rad(deg:Double)-> CGFloat {
                        return CGFloat(deg / 180.0 * Double.pi)
                    }
                    switch (image.imageOrientation)
                    {
                    case .left:
                        let rotationTransform = CGAffineTransform(rotationAngle: rad(deg: 90))
                        return rotationTransform.translatedBy(x: 0, y: -image.size.height)
                    case .right:
                        let rotationTransform = CGAffineTransform(rotationAngle: rad(deg: -90))
                        return rotationTransform.translatedBy(x: -image.size.width, y: 0)
                    case .down:
                        let rotationTransform = CGAffineTransform(rotationAngle: rad(deg: -180))
                        return rotationTransform.translatedBy(x: -image.size.width, y: -image.size.height)
                    default:
                        return CGAffineTransform.identity
                    }
                }
                
                cropRect = cropRect.applying(cropTransForm)
                
                guard let cgImage = image.cgImage else {
                    captureError(errorText: "Couldn't turn image into CGImage. Try retaking photo.")
                    return
                }
                guard let croppedImage = cgImage.cropping(to: cropRect) else {
                    captureError(errorText: "Couldn't crop image to apropriate size. Try retaking photo.")
                    return
                }
                let orientation = ALAssetOrientation(rawValue: image.imageOrientation.rawValue)!
                
                ALAssetsLibrary().writeImage(toSavedPhotosAlbum: croppedImage, orientation: orientation) {
                    (path, error) in
                    
                    self.notify(notification: .PhotoSaved)
                    
                    guard error == nil else {
                        
                        captureError(errorText: "Couldn't save photo.\n Try going to Settings > Privacy > Photos\n Then switch \(kAppName) to On")
                        return
                        
                    }
                    
                    // photo saved
                    
                }
            }
        }
        
    }
    
    
    // MARK: Utilities
    
    
    func _normalizeGains(g:AVCaptureDevice.WhiteBalanceGains) -> AVCaptureDevice.WhiteBalanceGains {
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
    
    func _normalizeGainsForTemperatureAndTint(tt:AVCaptureDevice.WhiteBalanceTemperatureAndTintValues) -> AVCaptureDevice.WhiteBalanceGains{
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
                        let nTT = camera.temperatureAndTintValues(for: _normalizeGains(g: eGains))
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
                            eGains = _normalizeGains(g: eGains)
                        }else{
                            eGains = camera.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: eTemperature, tint: eTint))
                        }
                        i += 1
                    }
                    g = eGains
                }else if abs(dTemp) < abs(dTint) {
                    while !_gainsInRange(gains: eGains) {
                        let nTT = camera.temperatureAndTintValues(for: _normalizeGains(g: eGains))
                        let eTintNew = round(nTT.tint)
                        let eTemperatureNew = round(nTT.temperature)
                        if eTemperature != eTemperatureNew {
                            eTemperature = eTemperatureNew
                        } else if eTint != eTintNew {
                            eTint = eTintNew
                        }
                        if i > 3 || (eTint == eTintNew && eTemperature == eTemperatureNew) {
                            eGains = _normalizeGains(g: eGains)
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
        return _normalizeGains(g: g)
    }
    
    func _gainsInRange(gains:AVCaptureDevice.WhiteBalanceGains) -> Bool {
        let maxGain = camera.maxWhiteBalanceGain
        let r = (1.0 <= gains.redGain && gains.redGain <= maxGain)
        let g = (1.0 <= gains.greenGain && gains.greenGain <= maxGain)
        let b = (1.0 <= gains.blueGain && gains.blueGain <= maxGain)
        return r && g && b
    }
}
