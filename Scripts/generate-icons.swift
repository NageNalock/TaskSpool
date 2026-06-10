#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct IconVariant {
    let filename: String
    let pixelSize: Int
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    fputs("Usage: generate-icons.swift <source-png> <resources-dir>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: arguments[1])
let resourcesURL = URL(fileURLWithPath: arguments[2], isDirectory: true)
let iconsetURL = resourcesURL.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let brandURL = resourcesURL.appendingPathComponent("Brand", isDirectory: true)
let statusIconURL = brandURL.appendingPathComponent("status-icon.png")
let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")

let variants = [
    IconVariant(filename: "icon_16x16.png", pixelSize: 16),
    IconVariant(filename: "icon_16x16@2x.png", pixelSize: 32),
    IconVariant(filename: "icon_32x32.png", pixelSize: 32),
    IconVariant(filename: "icon_32x32@2x.png", pixelSize: 64),
    IconVariant(filename: "icon_128x128.png", pixelSize: 128),
    IconVariant(filename: "icon_128x128@2x.png", pixelSize: 256),
    IconVariant(filename: "icon_256x256.png", pixelSize: 256),
    IconVariant(filename: "icon_256x256@2x.png", pixelSize: 512),
    IconVariant(filename: "icon_512x512.png", pixelSize: 512),
    IconVariant(filename: "icon_512x512@2x.png", pixelSize: 1024)
]

let icnsEntries: [(type: String, filename: String)] = [
    ("icp4", "icon_16x16.png"),
    ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"),
    ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"),
    ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

guard
    let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
    let sourceImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
else {
    fputs("Unable to read source image: \(sourceURL.path)\n", stderr)
    exit(1)
}

let fileManager = FileManager.default
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: brandURL, withIntermediateDirectories: true)

for variant in variants {
    let outputURL = iconsetURL.appendingPathComponent(variant.filename)
    try writePNG(resize(sourceImage, to: variant.pixelSize), to: outputURL)
}

try writePNG(resize(sourceImage, to: 64), to: statusIconURL)
try runIconutil(iconsetURL: iconsetURL, icnsURL: icnsURL)

func resize(_ sourceImage: CGImage, to pixelSize: Int) -> CGImage {
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fatalError("Unable to create image context for \(pixelSize)x\(pixelSize)")
    }

    context.interpolationQuality = .high
    context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))

    guard let resizedImage = context.makeImage() else {
        fatalError("Unable to render \(pixelSize)x\(pixelSize) image")
    }

    return resizedImage
}

func writePNG(_ image: CGImage, to outputURL: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        throw NSError(domain: "GenerateIcons", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Unable to create PNG destination: \(outputURL.path)"
        ])
    }

    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw NSError(domain: "GenerateIcons", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Unable to write PNG: \(outputURL.path)"
        ])
    }
}

func runIconutil(iconsetURL: URL, icnsURL: URL) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = [
        "-c", "icns",
        iconsetURL.path
    ]
    process.standardOutput = Pipe()
    process.standardError = Pipe()

    do {
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus == 0 {
            try copyDefaultICNSIfNeeded(iconsetURL: iconsetURL, icnsURL: icnsURL)
            return
        }
    } catch {
        // Fall through to the direct ICNS writer below.
    }

    // Some CommandLineTools builds reject transparent iconsets through iconutil.
    try writeICNS(iconsetURL: iconsetURL, icnsURL: icnsURL)
}

func copyDefaultICNSIfNeeded(iconsetURL: URL, icnsURL: URL) throws {
    let defaultICNSURL = iconsetURL.deletingPathExtension().appendingPathExtension("icns")
    if defaultICNSURL.standardizedFileURL != icnsURL.standardizedFileURL {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: icnsURL.path) {
            try fileManager.removeItem(at: icnsURL)
        }
        try fileManager.copyItem(at: defaultICNSURL, to: icnsURL)
    }
}

func writeICNS(iconsetURL: URL, icnsURL: URL) throws {
    var chunks: [(type: String, data: Data)] = []
    var totalLength = 8

    for entry in icnsEntries {
        let data = try Data(contentsOf: iconsetURL.appendingPathComponent(entry.filename))
        chunks.append((entry.type, data))
        totalLength += 8 + data.count
    }

    guard totalLength <= Int(UInt32.max) else {
        throw NSError(domain: "GenerateIcons", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "ICNS file is too large: \(totalLength) bytes"
        ])
    }

    var output = Data()
    output.reserveCapacity(totalLength)
    output.appendASCII("icns")
    output.appendBigEndianUInt32(UInt32(totalLength))

    for chunk in chunks {
        let chunkLength = 8 + chunk.data.count
        guard chunkLength <= Int(UInt32.max) else {
            throw NSError(domain: "GenerateIcons", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "ICNS chunk is too large: \(chunk.type)"
            ])
        }

        output.appendASCII(chunk.type)
        output.appendBigEndianUInt32(UInt32(chunkLength))
        output.append(chunk.data)
    }

    try output.write(to: icnsURL, options: .atomic)
}

extension Data {
    mutating func appendASCII(_ string: String) {
        append(string.data(using: .ascii)!)
    }

    mutating func appendBigEndianUInt32(_ value: UInt32) {
        var bigEndian = value.bigEndian
        Swift.withUnsafeBytes(of: &bigEndian) { buffer in
            append(contentsOf: buffer)
        }
    }
}
