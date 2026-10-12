// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "MLNotes",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "MLNotes", path: "Sources/MLNotes")]
)
