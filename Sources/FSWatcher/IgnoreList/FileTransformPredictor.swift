//
//  FileTransformPredictor.swift
//  FSWatcher
//
//  Created by FSWatcher on 2025/08/13.
//

import Foundation

/// Predicts output files based on input files and transformation rules
public struct FileTransformPredictor {
    
    /// A rule for predicting file transformations
    public struct TransformRule {
        /// The input file pattern (regex)
        public let inputPattern: String
        
        /// The output file template
        public let outputTemplate: String
        
        /// Whether the transformation changes the file format
        public let formatChange: Bool
        
        /// Initialize a transform rule
        /// - Parameters:
        ///   - inputPattern: The regex pattern for input files
        ///   - outputTemplate: The output file template (supports {name} and {ext} placeholders)
        ///   - formatChange: Whether the format changes
        public init(inputPattern: String, outputTemplate: String, formatChange: Bool = false) {
            self.inputPattern = inputPattern
            self.outputTemplate = outputTemplate
            self.formatChange = formatChange
        }
    }
    
    private let rules: [TransformRule]
    
    /// Initialize with transformation rules
    /// - Parameter rules: The transformation rules
    public init(rules: [TransformRule]) {
        self.rules = rules
    }
    
    /// Initialize with a single transformation rule
    /// - Parameter rule: The transformation rule
    public init(rule: TransformRule) {
        self.rules = [rule]
    }
    
    /// Predict output files for a given input file
    /// - Parameter inputURL: The input file URL
    /// - Returns: Predicted output file URLs
    public func predictOutputFiles(for inputURL: URL) -> [URL] {
        var outputs: [URL] = []
        
        let fileName = inputURL.deletingPathExtension().lastPathComponent
        let fileExtension = inputURL.pathExtension
        let directory = inputURL.deletingLastPathComponent()
        let fullFileName = inputURL.lastPathComponent
        
        for rule in rules {
            // Check if the input file matches the pattern
            if fullFileName.range(of: rule.inputPattern, options: .regularExpression) != nil {
                // Apply the template to generate output file name
                var outputName = rule.outputTemplate
                    .replacingOccurrences(of: "{name}", with: fileName)
                    .replacingOccurrences(of: "{ext}", with: fileExtension)
                
                // Handle special cases
                outputName = outputName
                    .replacingOccurrences(of: "{timestamp}", with: String(Int(Date().timeIntervalSince1970)))
                    .replacingOccurrences(of: "{date}", with: DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none))
                
                let outputURL = directory.appendingPathComponent(outputName)
                outputs.append(outputURL)
            }
        }
        
        return outputs
    }
    
    /// Predict output files for multiple input files
    /// - Parameter inputURLs: The input file URLs
    /// - Returns: All predicted output file URLs
    public func predictOutputFiles(for inputURLs: [URL]) -> [URL] {
        inputURLs.flatMap { predictOutputFiles(for: $0) }
    }
    
    // MARK: - Convenience Factory Methods
    
    /// Create a predictor for image compression
    /// - Parameter suffix: The suffix to add to compressed files
    /// - Returns: A predictor configured for image compression
    public static func imageCompression(suffix: String = "_compressed") -> FileTransformPredictor {
        FileTransformPredictor(rules: [
            TransformRule(
                inputPattern: ".*\\.(jpe?g|png|tiff?|bmp)$",
                outputTemplate: "{name}\(suffix).{ext}",
                formatChange: false
            )
        ])
    }
    
    /// Create a predictor for format conversion
    /// - Parameters:
    ///   - from: The source extension pattern
    ///   - to: The target extension
    /// - Returns: A predictor configured for format conversion
    public static func formatConversion(from: String, to: String) -> FileTransformPredictor {
        FileTransformPredictor(rules: [
            TransformRule(
                inputPattern: ".*\\.\(from)$",
                outputTemplate: "{name}.\(to)",
                formatChange: true
            )
        ])
    }
    
    /// Create a predictor for thumbnail generation
    /// - Parameters:
    ///   - prefix: The prefix for thumbnail files
    ///   - size: The size identifier to include in the name
    /// - Returns: A predictor configured for thumbnail generation
    public static func thumbnailGeneration(prefix: String = "thumb_", size: String = "") -> FileTransformPredictor {
        let sizeStr = size.isEmpty ? "" : "_\(size)"
        return FileTransformPredictor(rules: [
            TransformRule(
                inputPattern: ".*\\.(jpe?g|png|gif|webp)$",
                outputTemplate: "\(prefix){name}\(sizeStr).{ext}",
                formatChange: false
            )
        ])
    }
    
    /// Create a predictor for video transcoding
    /// - Parameter outputFormat: The output video format
    /// - Returns: A predictor configured for video transcoding
    public static func videoTranscoding(outputFormat: String = "mp4") -> FileTransformPredictor {
        FileTransformPredictor(rules: [
            TransformRule(
                inputPattern: ".*\\.(mov|avi|wmv|flv|mkv)$",
                outputTemplate: "{name}.\(outputFormat)",
                formatChange: true
            )
        ])
    }
    
    /// Create a predictor for document conversion
    /// - Returns: A predictor configured for document conversion
    public static func documentConversion() -> FileTransformPredictor {
        FileTransformPredictor(rules: [
            TransformRule(
                inputPattern: ".*\\.docx?$",
                outputTemplate: "{name}.pdf",
                formatChange: true
            ),
            TransformRule(
                inputPattern: ".*\\.md$",
                outputTemplate: "{name}.html",
                formatChange: true
            )
        ])
    }
}