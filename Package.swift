// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "swift-openapi-schema",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
    .tvOS(.v17),
    .watchOS(.v10),
    .macCatalyst(.v17),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "OpenAPISchema", targets: ["OpenAPISchema"])
  ],
  dependencies: [
    .package(url: "https://github.com/ajevans99/swift-json-schema.git", from: "0.12.0"),
    .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.17.6"),
  ],
  targets: [
    .target(
      name: "OpenAPISchema",
      dependencies: [
        .product(name: "JSONSchema", package: "swift-json-schema"),
        .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
      ],
      resources: [
        .process("Resources")
      ]
    ),
    .testTarget(
      name: "OpenAPISchemaTests",
      dependencies: [
        "OpenAPISchema",
        .product(name: "JSONSchema", package: "swift-json-schema"),
        .product(name: "JSONSchemaBuilder", package: "swift-json-schema"),
        .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
      ],
      exclude: ["__Snapshots__"]
    ),
  ],
  swiftLanguageModes: [.v6]
)
