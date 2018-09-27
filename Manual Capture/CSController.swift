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

enum SessionError : Error {
    enum InputError : Error {
        case AccessDenied
        case CannotAddToSession
        case CannotConnect
        case InitFailed(Error?)
    }
    enum OutputError : Error {
        case CannotAddToSession
        case CannotConnect
    }
    case NoCameraForPosition
    case CameraInputError(InputError)
    case AudioInputError(InputError)
    case CameraAccessDenied
    case PhotoOutputError(OutputError)
    case VideoOutputError(OutputError)
}

// MARK: Delegate Protocol

protocol CSControllerDelegate {
    func sessionControllerError(error: Error)
    func sessionControllerNotification(notification:CSNotification)
}

// change type
enum CSChange {
    enum ExposureType {
        case ISO(Float), TargetOffset(Float), Duration(CMTime)
        case Bias(Float)
        
        case MinISO(Float), MaxISO(Float)
        case MinDuration(CMTime), MaxDuration(CMTime)
    }
    case LensPosition(Float)
    case Exposure(ExposureType)
    case WhiteBalanceGains(AVCaptureDevice.WhiteBalanceGains)
    case ZoomFactor(CGFloat)
    case AspectRatio(CSAspectRatio)
    
    
    case FocusMode(AVCaptureDevice.FocusMode)
    case ExposureMode(AVCaptureDevice.ExposureMode)
    case WhiteBalanceMode(AVCaptureDevice.WhiteBalanceMode)
    case AspectRatioMode(CSAspectRatioMode)
}

// value set type
enum CSSet {
    enum ExposureType {
        case Bias(Float)
        case DurationAndISO(CMTime, Float)
    }
    case LensPosition(Float)
    case Exposure(ExposureType)
    case WhiteBalanceGains(AVCaptureDevice.WhiteBalanceGains)
    case ZoomFactor(CGFloat), ZoomFactorRamp(CGFloat, Float)
    case AspectRatio(CSAspectRatio)
    
    
    case FocusMode(AVCaptureDevice.FocusMode)
    case ExposureMode(AVCaptureDevice.ExposureMode)
    case WhiteBalanceMode(AVCaptureDevice.WhiteBalanceMode)
    case AspectRatioMode(CSAspectRatioMode)
}

// notification type
enum CSNotification {
    case CapturingPhoto(Bool)
    case PhotoSaved
    case SubjectAreaChange
    case SessionRunning(Bool)
}

typealias CSAspectRatio = CGFloat
func CSAspectRatioMake(_ width: CGFloat, _ height: CGFloat) -> CSAspectRatio {
    return width / height
}

enum CSAspectRatioMode: Int {
    case Lock, Fullscreen, Sensor
}

class CSController: NSObject, AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        <#code#>
    }
    
    
    private var _notifObservers: [ String : AnyObject? ] = [ : ]
    typealias KVOContext = UInt8
    private var _context: [ String : KVOContext ] = [ : ]
    
    let session: AVCaptureSession
    let sessionQueue: DispatchQueue
    let previewLayer: CapturePreviewLayer
    // KVO
    @objc dynamic var camera: AVCaptureDevice!
    var cameraInput: AVCaptureDeviceInput!
    var audioInput: AVCaptureDeviceInput!
    // KVO
    @objc dynamic var photoOutput: AVCaptureStillImageOutput!
    var videoOutput: AVCaptureMovieFileOutput!
    var backgroundRecordingID: UIBackgroundTaskIdentifier!
    
    var aspectRatio = CSAspectRatioMake(16,9) {
        didSet{
            
            previewLayer.aspectRatio = aspectRatio
            notify(change: .AspectRatio(aspectRatio) )
            
        }
    }
    var aspectRatioMode: CSAspectRatioMode = .Fullscreen {
        didSet{
            updateAspectRatio()
            notify(change: .AspectRatioMode(aspectRatioMode) )
        }
    }
    func updateAspectRatio() {
        guard previewLayer.connection != nil else { return }
        switch aspectRatioMode {
        case .Lock:
            let aspectRatio = self.aspectRatio
            self.aspectRatio = aspectRatio
        case .Fullscreen:
            let size = previewLayer.requestedBound?.size ?? UIScreen.main.bounds.size
            self.aspectRatio = CSAspectRatioMake(size.width, size.height)
        case .Sensor:
            let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            let size = previewLayer.layerRectConverted(fromMetadataOutputRect: unitRect).size
            self.aspectRatio = CSAspectRatioMake(size.width, size.height)
        }
    }
    
    var volumeButtonHandler: JPSVolumeButtonHandler?
    
    var delegate: CSControllerDelegate?
    
    struct VOBlocks {
        
        typealias LensPositionBlock = (Float) -> ()
        typealias ISOBlock = (Float) -> ()
        typealias ExposureDurationBlock = (CMTime) -> ()
        typealias TargetOffsetBlock = (Float) -> ()
        typealias TargetBiasBlock = (Float) -> ()
        typealias WhiteBalanceGainsBlock = (AVCaptureDevice.WhiteBalanceGains) -> ()
        typealias ZoomFactorBlock = (CGFloat) -> ()
        typealias AspectRatioBlock = (CSAspectRatio) -> ()
        
        typealias FocusModeBlock = (AVCaptureDevice.FocusMode) -> ()
        typealias ExposureModeBlock = (AVCaptureDevice.ExposureMode) -> ()
        typealias WhiteBalanceModeBlock = (AVCaptureDevice.WhiteBalanceMode) -> ()
        typealias AspectRatioModeBlock = (CSAspectRatioMode) -> ()
        
        var lensPosition        = [ String : LensPositionBlock ]()
        var iso                 = [ String : ISOBlock ]()
        var exposureDuration    = [ String : ExposureDurationBlock ]()
        var targetOffset        = [ String : TargetOffsetBlock ]()
        var targetBias          = [ String : TargetOffsetBlock ]()
        var whiteBalance        = [ String : WhiteBalanceGainsBlock ]()
        var zoomFactor          = [ String : ZoomFactorBlock ]()
        var aspectRatio         = [ String : AspectRatioBlock ]()
        
        var focusMode           = [ String : FocusModeBlock ]()
        var exposureMode        = [ String : ExposureModeBlock ]()
        var whiteBalanceMode    = [ String : WhiteBalanceModeBlock ]()
        var aspectRatioMode     = [ String : AspectRatioModeBlock ]()
        
    }
    var voBlocks = VOBlocks()
    var observers = [NSKeyValueObservation]()
    
    override init() {
        session = AVCaptureSession()
        session.sessionPreset = kIsVideoMode ? AVCaptureSession.Preset.high : AVCaptureSession.Preset.photo
        
        sessionQueue = DispatchQueue(label: "com.manual-camera.session")
        
        previewLayer = CapturePreviewLayer(session: session)
        previewLayer.aspectRatio = aspectRatio
        
        volumeButtonHandler = !kIsVideoMode ? JPSVolumeButtonHandler() : nil
        
        super.init()
        
        unowned let me = self
        volumeButtonHandler?.action = { me.captureStillPhoto() }
        if !kIsDemoMode {
            requestCameraAccess(){
                self.startCamera()
            }
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
            
            func getCamera(position: AVCaptureDevice.Position) throws -> AVCaptureDevice {
                if #available(iOS 10.0, *), let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)  {
                    return device
                } else if let device = AVCaptureDevice.`default`(for: .video), device.position == position {
                    return device
                } else {
                    let devices = AVCaptureDevice.devices(for: .video).filter() { $0.position == position }
                    if !devices.isEmpty {
                        return devices[0]
                    }
                }
                throw SessionError.NoCameraForPosition
            }
            
            func addCameraInputFromCamera(camera:AVCaptureDevice) throws {
                
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
                
                guard let connection = previewLayer.connection else {
                    throw SessionError.CameraInputError(.CannotConnect)
                }
                
                let statusBarOrientation = UIApplication.shared.statusBarOrientation
                connection.videoOrientation = AVCaptureVideoOrientation(ui: statusBarOrientation)
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
                
            }
            
            func addAudioInput() throws {
                do {
                    guard let audioDevice = AVCaptureDevice.default(for: AVMediaType.audio) else {
                        throw SessionError.AudioInputError(.InitFailed(nil))
                    }
                    audioInput = try AVCaptureDeviceInput(device: audioDevice)
                }
                catch {
                    throw SessionError.AudioInputError(.InitFailed(error))
                }
                guard session.canAddInput(audioInput) else {
                    throw SessionError.AudioInputError(.CannotAddToSession)
                }
                session.addInput(audioInput)
            }
            
            func addPhotoOutput() throws {
                photoOutput = AVCaptureStillImageOutput()
                guard session.canAddOutput(photoOutput) else {
                    throw SessionError.PhotoOutputError(.CannotAddToSession)
                }
                photoOutput.isHighResolutionStillImageOutputEnabled = true
                session.addOutput(photoOutput)
            }
            
            func addVideoOutput() throws {
                videoOutput =  AVCaptureMovieFileOutput()
                guard session.canAddOutput(videoOutput) else {
                    throw SessionError.VideoOutputError(.CannotAddToSession)
                }
                session.addOutput(videoOutput)
                guard let connection = videoOutput.connection(with: .video) else {
                    throw SessionError.VideoOutputError(.CannotConnect)
                }
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            
            do {
                session.beginConfiguration()
                backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
                if camera == nil {
                    try camera = getCamera(position: .back)
                }
                if cameraInput == nil {
                    try addCameraInputFromCamera(camera: camera)
                }
                if photoOutput == nil {
                    try addPhotoOutput()
                }
                if kIsVideoMode {
                    if audioInput == nil {
                        try addAudioInput()
                    }
                    if videoOutput == nil {
                        try addVideoOutput()
                    }
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
        case .AspectRatio(let v): self.voBlocks.aspectRatio.forEach { $1(v) }
            
        case .FocusMode(let v): self.voBlocks.focusMode.forEach { $1(v) }
        case .ExposureMode(let v): self.voBlocks.exposureMode.forEach { $1(v) }
        case .WhiteBalanceMode(let v): self.voBlocks.whiteBalanceMode.forEach { $1(v) }
        case .AspectRatioMode(let v): self.voBlocks.aspectRatioMode.forEach { $1(v) }
            
        default : break
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
            } catch {
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
            self.aspectRatioMode = .Lock
            self.aspectRatio = aspectRatio
        case .AspectRatioMode(let mode):
            self.aspectRatioMode = mode
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
            connection.videoOrientation = self.previewLayer.connection?.videoOrientation ?? .landscapeRight
            
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
    
    
    func captureVideo() {
        
        sessionQueue.async(){
            if !self.videoOutput.isRecording {
                
                var me = self
                let unsafeMe = UnsafeMutablePointer<CSController>.allocate(capacity: 1)
                unsafeMe.initialize(to: me)
                
                AudioServicesAddSystemSoundCompletion(1117, nil, nil, { _, userData in
                    let unsafeMe = unsafeBitCast(userData, to: UnsafeMutablePointer<CSController>.self)
                    var me: CSController { return unsafeMe.pointee }
                    
                    // start recording
                    if UIDevice.current.isMultitaskingSupported {
                        me.backgroundRecordingID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                    }
                    
                    if let recordingConnection = me.videoOutput.connection(with: AVMediaType.video),
                        let previewConnection = me.previewLayer.connection {
                        recordingConnection.videoOrientation = previewConnection.videoOrientation
                    } else {
                        me.notify(error: SessionError.OutputError.CannotConnect)
                    }
                    let videoFileName = ProcessInfo.processInfo.globallyUniqueString
                    let videoFilePath = NSTemporaryDirectory().appendingFormat(videoFileName + ".mov")
                    
                    me.videoOutput.startRecording(
                        to: NSURL(fileURLWithPath: videoFilePath) as URL, recordingDelegate: me)
                    
                    
                    AudioServicesRemoveSystemSoundCompletion(1117)
                    
                    unsafeMe.deinitialize(count: 1)
                    unsafeMe.deallocate()
                    
                }, unsafeMe)
                
                AudioServicesPlaySystemSound(1117)
                
            }else{
                self.videoOutput.stopRecording()
            }
        }
    
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didStartRecordingToOutputFileAtURL fileURL: NSURL!, fromConnections connections: [AnyObject]!) {
        
        //AudioServicesPlaySystemSound(1117)
    }
    
    func captureOutput(captureOutput: AVCaptureFileOutput!, didFinishRecordingToOutputFileAtURL outputFileURL: NSURL!, fromConnections connections: [AnyObject]!, error: NSError!) {
        
        AudioServicesPlaySystemSound(1118)
        
        let currentBackgroundRecordingID = backgroundRecordingID
        backgroundRecordingID = UIBackgroundTaskIdentifier.invalid
        
        let cleanup = {
            do {
                try FileManager.default.removeItem(at: outputFileURL as URL)
            } catch {
                
            }
            if currentBackgroundRecordingID != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(currentBackgroundRecordingID!)
            }
        }
        
        if error == nil {
            PHPhotoLibrary.requestAuthorization { status in
                guard status == .authorized else { cleanup(); return }
                PHPhotoLibrary.shared().performChanges({
                    if #available(iOS 9.0, *) {
                        let options = PHAssetResourceCreationOptions()
                        options.shouldMoveFile = true
                        let changeRequest = PHAssetCreationRequest.forAsset()
                        changeRequest.addResource(with: .video, fileURL: outputFileURL as URL, options: options)
                    } else {
                        // Fallback on earlier versions
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: outputFileURL as URL)
                    }
                    
                    }, completionHandler: { success, error in
                
                        if ( !success ) {
                            print( "Could not save movie to photo library: ", error ?? "" )
                        }
                        cleanup()
                })
            }
        }else{
            print( "Could not save movie to photo library: ", error )
            cleanup()
        }
    }
    
    // MARK: Utilities
    
    func _normalizeGains( g:AVCaptureDevice.WhiteBalanceGains) -> AVCaptureDevice.WhiteBalanceGains{
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
                        if eTint != eTintNew {eTint = eTintNew}
                        else if eTemperature != eTemperatureNew {eTemperature = eTemperatureNew}
                        if i > 3 || (eTint == eTintNew && eTemperature == eTemperatureNew) {
                            eGains = _normalizeGains(g: eGains)
                        }else{
                            eGains = camera.deviceWhiteBalanceGains(for: AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: eTemperature, tint: eTint))
                        }
                        i += 1
                    }
                    g = eGains
                } else if abs(dTemp) < abs(dTint) {
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
    
    func _gainsInRange(gains: AVCaptureDevice.WhiteBalanceGains) -> Bool {
        let maxGain = camera.maxWhiteBalanceGain
        let r = (1.0 <= gains.redGain && gains.redGain <= maxGain)
        let g = (1.0 <= gains.greenGain && gains.greenGain <= maxGain)
        let b = (1.0 <= gains.blueGain && gains.blueGain <= maxGain)
        return r && g && b
        
    }
}
