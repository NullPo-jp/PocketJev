import AVFoundation
import Observation
import UIKit

@MainActor
@Observable
final class CameraService: NSObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    var authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    var lastError: String?

    private let photoOutput = AVCapturePhotoOutput()
    private var configured = false
    private var continuation: CheckedContinuation<UIImage, Error>?

    func start() async {
        if authorizationStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationStatus = granted ? .authorized : .denied
        }
        guard authorizationStatus == .authorized else { return }

        do {
            try configureIfNeeded()
            if !session.isRunning {
                session.startRunning()
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    func capture() async throws -> UIImage {
        guard configured, session.isRunning else { throw PocketJevError.cameraUnavailable }
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let settings = AVCapturePhotoSettings()
            settings.photoQualityPrioritization = .speed
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    private func configureIfNeeded() throws {
        guard !configured else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw PocketJevError.cameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            throw PocketJevError.cameraUnavailable
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        photoOutput.maxPhotoQualityPrioritization = .speed
        configured = true
    }

    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // AVCapturePhoto is not Sendable. Extract immutable bytes before hopping
        // back to MainActor so Swift 6 does not carry the AVFoundation object
        // across isolation domains.
        let data = photo.fileDataRepresentation()
        let captureFailed = error != nil
        Task { @MainActor in
            guard let continuation = self.continuation else { return }
            self.continuation = nil

            if captureFailed {
                continuation.resume(throwing: PocketJevError.cameraUnavailable)
                return
            }
            guard let data, let image = UIImage(data: data) else {
                continuation.resume(throwing: PocketJevError.imageEncodingFailed)
                return
            }
            continuation.resume(returning: image)
        }
    }
}
