//
//  FilterTests.swift
//  FSWatcherTests
//
//  Created by okooo5km(十里) on 2025/08/13.
//

import XCTest
import UniformTypeIdentifiers
@testable import FSWatcher

final class FilterTests: XCTestCase {
    
    var tempDirectory: URL!
    
    override func setUpWithError() throws {
        // Create a temporary directory for testing
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("FilterTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDownWithError() throws {
        // Clean up
        try? FileManager.default.removeItem(at: tempDirectory)
    }
    
    func testFileExtensionFilter() throws {
        let filter = FileFilter.fileExtensions(["txt", "md"])
        
        let txtFile = tempDirectory.appendingPathComponent("test.txt")
        let mdFile = tempDirectory.appendingPathComponent("readme.md")
        let pdfFile = tempDirectory.appendingPathComponent("document.pdf")
        
        // Create test files
        try "".write(to: txtFile, atomically: true, encoding: .utf8)
        try "".write(to: mdFile, atomically: true, encoding: .utf8)
        try Data().write(to: pdfFile)
        
        XCTAssertTrue(filter.matches(txtFile))
        XCTAssertTrue(filter.matches(mdFile))
        XCTAssertFalse(filter.matches(pdfFile))
    }
    
    @available(macOS 11.0, iOS 14.0, *)
    func testUTTypeFilter() throws {
        
        let filter = FileFilter.imageFiles
        
        let jpegFile = tempDirectory.appendingPathComponent("photo.jpg")
        let pngFile = tempDirectory.appendingPathComponent("image.png")
        let textFile = tempDirectory.appendingPathComponent("document.txt")
        
        // Create test files
        try Data().write(to: jpegFile)
        try Data().write(to: pngFile)
        try "".write(to: textFile, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(filter.matches(jpegFile))
        XCTAssertTrue(filter.matches(pngFile))
        XCTAssertFalse(filter.matches(textFile))
    }
    
    func testFileNamePatternFilter() {
        let filter = FileFilter.fileName(matching: "^test.*\\.txt$")
        
        let matchingFile1 = URL(fileURLWithPath: "/tmp/test.txt")
        let matchingFile2 = URL(fileURLWithPath: "/tmp/test123.txt")
        let nonMatchingFile1 = URL(fileURLWithPath: "/tmp/other.txt")
        let nonMatchingFile2 = URL(fileURLWithPath: "/tmp/test.pdf")
        
        XCTAssertTrue(filter.matches(matchingFile1))
        XCTAssertTrue(filter.matches(matchingFile2))
        XCTAssertFalse(filter.matches(nonMatchingFile1))
        XCTAssertFalse(filter.matches(nonMatchingFile2))
    }
    
    func testFileSizeFilter() throws {
        let filter = FileFilter.fileSize(1000...5000)
        
        let smallFile = tempDirectory.appendingPathComponent("small.txt")
        let mediumFile = tempDirectory.appendingPathComponent("medium.txt")
        let largeFile = tempDirectory.appendingPathComponent("large.txt")
        
        // Create files of different sizes
        try Data(repeating: 0, count: 500).write(to: smallFile)
        try Data(repeating: 0, count: 2000).write(to: mediumFile)
        try Data(repeating: 0, count: 10000).write(to: largeFile)
        
        XCTAssertFalse(filter.matches(smallFile))
        XCTAssertTrue(filter.matches(mediumFile))
        XCTAssertFalse(filter.matches(largeFile))
    }
    
    func testFilterCombinations() {
        let extensionFilter = FileFilter.fileExtensions(["txt"])
        let patternFilter = FileFilter.fileName(matching: "^test")
        
        // AND combination
        let andFilter = extensionFilter.and(patternFilter)
        XCTAssertTrue(andFilter.matches(URL(fileURLWithPath: "/tmp/test.txt")))
        XCTAssertFalse(andFilter.matches(URL(fileURLWithPath: "/tmp/other.txt")))
        XCTAssertFalse(andFilter.matches(URL(fileURLWithPath: "/tmp/test.pdf")))
        
        // OR combination
        let orFilter = extensionFilter.or(patternFilter)
        XCTAssertTrue(orFilter.matches(URL(fileURLWithPath: "/tmp/test.txt")))
        XCTAssertTrue(orFilter.matches(URL(fileURLWithPath: "/tmp/other.txt")))
        XCTAssertTrue(orFilter.matches(URL(fileURLWithPath: "/tmp/test.pdf")))
        XCTAssertFalse(orFilter.matches(URL(fileURLWithPath: "/tmp/other.pdf")))
        
        // NOT
        let notFilter = extensionFilter.not()
        XCTAssertFalse(notFilter.matches(URL(fileURLWithPath: "/tmp/file.txt")))
        XCTAssertTrue(notFilter.matches(URL(fileURLWithPath: "/tmp/file.pdf")))
    }
    
    func testFilterChain() {
        var chain = FilterChain()
        
        // Initially empty chain matches everything
        XCTAssertTrue(chain.isEmpty)
        XCTAssertTrue(chain.matches(URL(fileURLWithPath: "/tmp/any.file")))
        
        // Add filters
        chain.add(FileFilter.fileExtensions(["txt", "md"]))
        chain.add(FileFilter.fileName(matching: "^README"))
        
        // Both filters must match (AND logic)
        XCTAssertTrue(chain.matches(URL(fileURLWithPath: "/tmp/README.txt")))
        XCTAssertTrue(chain.matches(URL(fileURLWithPath: "/tmp/README.md")))
        XCTAssertFalse(chain.matches(URL(fileURLWithPath: "/tmp/README.pdf")))
        XCTAssertFalse(chain.matches(URL(fileURLWithPath: "/tmp/OTHER.txt")))
        
        // Test filtering arrays
        let urls = [
            URL(fileURLWithPath: "/tmp/README.txt"),
            URL(fileURLWithPath: "/tmp/README.md"),
            URL(fileURLWithPath: "/tmp/README.pdf"),
            URL(fileURLWithPath: "/tmp/OTHER.txt")
        ]
        
        let filtered = chain.filter(urls)
        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains(URL(fileURLWithPath: "/tmp/README.txt")))
        XCTAssertTrue(filtered.contains(URL(fileURLWithPath: "/tmp/README.md")))
    }
    
    func testDirectoryFilter() throws {
        let dirFilter = FileFilter.directoriesOnly
        let fileFilter = FileFilter.filesOnly
        
        let directory = tempDirectory.appendingPathComponent("subdir")
        let file = tempDirectory.appendingPathComponent("file.txt")
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "content".write(to: file, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(dirFilter.matches(directory))
        XCTAssertFalse(dirFilter.matches(file))
        
        XCTAssertFalse(fileFilter.matches(directory))
        XCTAssertTrue(fileFilter.matches(file))
    }
    
    func testModificationDateFilter() throws {
        let filter = FileFilter.modifiedWithin(3600) // Within last hour
        
        let recentFile = tempDirectory.appendingPathComponent("recent.txt")
        try "content".write(to: recentFile, atomically: true, encoding: .utf8)
        
        XCTAssertTrue(filter.matches(recentFile))
        
        // Note: Testing old files would require manipulating file timestamps
        // which is complex and platform-dependent
    }
}