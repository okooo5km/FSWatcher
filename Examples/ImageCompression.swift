//
//  ImageCompression.swift
//  FSWatcher Examples - Image Compression Pipeline
//
//  Created by FSWatcher on 2025/08/13.
//

import Foundation
import FSWatcher
import CoreImage
import UniformTypeIdentifiers

/// A complete image compression pipeline example similar to Zipic
class ImageCompressionPipeline {
    
    private let watcher: DirectoryWatcher
    private let compressionQueue = OperationQueue()
    private let outputDirectory: URL
    private let compressionQuality: CGFloat
    
    init(watchDirectory: URL, outputDirectory: URL? = nil, compressionQuality: CGFloat = 0.8) throws {
        self.outputDirectory = outputDirectory ?? watchDirectory
        self.compressionQuality = compressionQuality
        
        // Configure watcher
        var config = DirectoryWatcher.Configuration()
        
        // Only watch image files larger than 1KB
        if #available(macOS 11.0, iOS 14.0, *) {
            config.filterChain.add(.imageFiles)
        } else {
            config.filterChain.add(.fileExtensions(["jpg", "jpeg", "png", "tiff", "bmp"]))
        }
        config.filterChain.add(.fileSize(1024...))
        
        // Set up transform predictor to avoid processing our own output
        let predictor = FileTransformPredictor(rules: [
            FileTransformPredictor.TransformRule(
                inputPattern: "^(?!.*_compressed).*\\.(jpe?g|png|tiff?|bmp)$",
                outputTemplate: "{name}_compressed.jpg",
                formatChange: true
            )
        ])
        config.transformPredictor = predictor
        
        // Initialize watcher
        self.watcher = try DirectoryWatcher(url: watchDirectory, configuration: config)
        
        // Configure compression queue
        compressionQueue.maxConcurrentOperationCount = 4
        compressionQueue.qualityOfService = .userInitiated
        
        // Set up event handler
        watcher.onFilteredChange = { [weak self] newImages in
            self?.processNewImages(newImages)
        }
        
        watcher.onError = { error in
            print("Watcher error: \(error)")
        }
    }
    
    func start() {
        watcher.start()
        print("Image compression pipeline started")
        print("Watching directory: \(watcher.isWatching ? "Active" : "Inactive")")
    }
    
    func stop() {
        watcher.stop()
        compressionQueue.cancelAllOperations()
        print("Image compression pipeline stopped")
    }
    
    private func processNewImages(_ images: [URL]) {
        print("\nDetected \(images.count) new images to process:")
        
        for imageURL in images {
            // Skip if already compressed
            if imageURL.lastPathComponent.contains("_compressed") {
                continue
            }
            
            // Predict output file and add to ignore list
            let outputURL = outputDirectory
                .appendingPathComponent(imageURL.deletingPathExtension().lastPathComponent + "_compressed")
                .appendingPathExtension("jpg")
            
            watcher.addPredictiveIgnore([outputURL])
            
            // Create compression operation
            let operation = ImageCompressionOperation(
                inputURL: imageURL,
                outputURL: outputURL,
                quality: compressionQuality
            )
            
            operation.completionBlock = { [weak self] in
                if operation.isSuccessful {
                    print("✓ Compressed: \(imageURL.lastPathComponent) -> \(outputURL.lastPathComponent)")
                    print("  Size reduction: \(operation.compressionRatio)%")
                    
                    // Add to ignore list after successful compression
                    self?.watcher.addIgnoredFiles([outputURL])
                } else if let error = operation.error {
                    print("✗ Failed to compress \(imageURL.lastPathComponent): \(error)")
                }
            }
            
            compressionQueue.addOperation(operation)
        }
    }
}

/// Operation for compressing a single image
class ImageCompressionOperation: Operation {
    
    let inputURL: URL
    let outputURL: URL
    let quality: CGFloat
    
    private(set) var isSuccessful = false
    private(set) var error: Error?
    private(set) var compressionRatio: Int = 0
    
    init(inputURL: URL, outputURL: URL, quality: CGFloat) {
        self.inputURL = inputURL
        self.outputURL = outputURL
        self.quality = quality
        super.init()
    }
    
    override func main() {
        guard !isCancelled else { return }
        
        do {
            // Get original file size
            let originalSize = try inputURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            
            // Load image
            guard let imageData = try? Data(contentsOf: inputURL),
                  let image = CIImage(data: imageData) else {
                throw CompressionError.invalidImage
            }
            
            guard !isCancelled else { return }
            
            // Compress image
            let context = CIContext()
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            
            guard let jpegData = context.jpegRepresentation(
                of: image,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: quality]
            ) else {
                throw CompressionError.compressionFailed
            }
            
            guard !isCancelled else { return }
            
            // Write compressed image
            try jpegData.write(to: outputURL)
            
            // Calculate compression ratio
            let compressedSize = jpegData.count
            if originalSize > 0 {
                compressionRatio = Int(((Double(originalSize - compressedSize) / Double(originalSize)) * 100))
            }
            
            isSuccessful = true
            
        } catch {
            self.error = error
            isSuccessful = false
        }
    }
}

enum CompressionError: LocalizedError {
    case invalidImage
    case compressionFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Could not load image"
        case .compressionFailed:
            return "Failed to compress image"
        }
    }
}

// MARK: - Advanced Pipeline with Format Conversion

class AdvancedImagePipeline {
    
    private let watcher: DirectoryWatcher
    private let processingQueue = DispatchQueue(label: "image.processing", attributes: .concurrent)
    private let settings: ProcessingSettings
    
    struct ProcessingSettings {
        var outputFormat: OutputFormat = .jpeg
        var quality: CGFloat = 0.85
        var maxDimension: CGFloat? = 2048
        var preserveMetadata: Bool = false
        
        enum OutputFormat {
            case jpeg
            case png
            case webp
            case heif
        }
    }
    
    init(watchDirectory: URL, settings: ProcessingSettings = ProcessingSettings()) throws {
        self.settings = settings
        
        var config = DirectoryWatcher.Configuration()
        
        // Configure filters
        if #available(macOS 11.0, iOS 14.0, *) {
            config.filterChain.add(.imageFiles)
        }
        
        // Predict output based on format
        let outputExtension: String
        switch settings.outputFormat {
        case .jpeg: outputExtension = "jpg"
        case .png: outputExtension = "png"
        case .webp: outputExtension = "webp"
        case .heif: outputExtension = "heic"
        }
        
        config.transformPredictor = FileTransformPredictor(rules: [
            FileTransformPredictor.TransformRule(
                inputPattern: ".*\\.(jpe?g|png|tiff?|bmp|gif)$",
                outputTemplate: "{name}_processed.\(outputExtension)",
                formatChange: true
            )
        ])
        
        self.watcher = try DirectoryWatcher(url: watchDirectory, configuration: config)
        
        setupEventHandlers()
    }
    
    private func setupEventHandlers() {
        watcher.onFilteredChange = { [weak self] newImages in
            guard let self = self else { return }
            
            for imageURL in newImages {
                self.processingQueue.async {
                    self.processImage(imageURL)
                }
            }
        }
    }
    
    private func processImage(_ inputURL: URL) {
        print("Processing: \(inputURL.lastPathComponent)")
        
        // Implementation would include:
        // - Image loading and validation
        // - Format conversion
        // - Resizing if needed
        // - Metadata preservation
        // - Writing output file
        
        // For brevity, using simplified version
        let outputURL = inputURL.deletingPathExtension()
            .appendingPathExtension("_processed")
            .appendingPathExtension("jpg")
        
        // Add to ignore list
        watcher.addIgnoredFiles([outputURL])
        
        print("Processed: \(inputURL.lastPathComponent) -> \(outputURL.lastPathComponent)")
    }
    
    func start() {
        watcher.start()
        print("Advanced image pipeline started")
    }
    
    func stop() {
        watcher.stop()
        print("Advanced image pipeline stopped")
    }
}

// MARK: - Main Example

func runImageCompressionExample() {
    print("Image Compression Pipeline Example")
    print("==================================\n")
    
    // Get Desktop folder as watch directory
    let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
    let watchDirectory = desktopURL.appendingPathComponent("ImageWatch")
    
    // Create watch directory if it doesn't exist
    try? FileManager.default.createDirectory(at: watchDirectory, withIntermediateDirectories: true)
    
    print("Watch directory: \(watchDirectory.path)")
    print("Drop images into this directory to compress them automatically\n")
    
    do {
        // Create and start the pipeline
        let pipeline = try ImageCompressionPipeline(
            watchDirectory: watchDirectory,
            compressionQuality: 0.7
        )
        
        pipeline.start()
        
        print("Pipeline is running. Press Ctrl+C to stop.\n")
        
        // Keep running
        RunLoop.main.run()
        
    } catch {
        print("Error starting pipeline: \(error)")
    }
}

// Run the example
runImageCompressionExample()