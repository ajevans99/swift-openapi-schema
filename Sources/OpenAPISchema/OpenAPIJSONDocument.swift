import Foundation
import OrderedJSON

/// The retrieval URI and RFC 6901 pointer of a value in an unmodified source document.
public struct OpenAPISourceLocation: Sendable, Hashable, CustomStringConvertible {
  public let sourceURI: URL?
  public let pointer: String

  public init(sourceURI: URL? = nil, pointer: String = "") {
    self.sourceURI = sourceURI
    self.pointer = pointer
  }

  public var description: String {
    "\(sourceURI?.absoluteString ?? "<document>")#\(pointer)"
  }

  public func appending(_ token: String) -> Self {
    let escaped = token.replacingOccurrences(of: "~", with: "~0")
      .replacingOccurrences(of: "/", with: "~1")
    return Self(sourceURI: sourceURI, pointer: "\(pointer)/\(escaped)")
  }
}

public struct OpenAPIImportError: Error, Sendable, Equatable, CustomStringConvertible {
  public let location: OpenAPISourceLocation
  public let message: String

  public init(location: OpenAPISourceLocation, message: String) {
    self.location = location
    self.message = message
  }

  public var description: String { "\(location): \(message)" }
}

/// Raw data with its original location, including for values in supplied external documents.
public struct OpenAPILocatedValue: Sendable, Equatable {
  public let value: JSONValue
  public let location: OpenAPISourceLocation

  public init(value: JSONValue, location: OpenAPISourceLocation) {
    self.value = value
    self.location = location
  }

  public func member(_ name: String) throws -> Self? {
    guard case .object(let object) = value else {
      throw error("Expected an object.")
    }
    return object[name].map { Self(value: $0, location: location.appending(name)) }
  }

  func error(_ message: String) -> OpenAPIImportError {
    OpenAPIImportError(location: location, message: message)
  }

  func object() throws -> JSONObject {
    guard case .object(let object) = value else { throw error("Expected an object.") }
    return object
  }

  func elements() throws -> [Self] {
    guard case .array(let values) = value else { throw error("Expected an array.") }
    return values.enumerated().map {
      Self(value: $0.element, location: location.appending(String($0.offset)))
    }
  }

  func string() throws -> String {
    guard case .string(let string) = value else { throw error("Expected a string.") }
    return string
  }

  func string(_ key: String, required: Bool = false) throws -> String? {
    guard let node = try member(key) else {
      if required {
        throw OpenAPIImportError(
          location: location.appending(key), message: "Required field is missing.")
      }
      return nil
    }
    return try node.string()
  }

  func boolean(_ key: String, default defaultValue: Bool = false) throws -> Bool {
    guard let node = try member(key) else { return defaultValue }
    guard case .boolean(let value) = node.value else { throw node.error("Expected a boolean.") }
    return value
  }

  func schema() throws -> Self {
    switch value {
    case .object, .boolean: return self
    default: throw error("Expected a JSON Schema object or boolean.")
    }
  }
}

/// Lossless semantic JSON ingestion, independent of full OpenAPI validation.
///
/// Object order, number tokens, unknown fields, and raw Schema and Reference Objects are
/// retained. Whitespace, string escape spelling, and duplicate object members are not:
/// OrderedJSON uses last-write-wins for duplicate members.
public struct OpenAPIJSONDocument: Sendable {
  public let rawValue: JSONValue
  public let sourceURI: URL?
  public let version: String
  public let externalDocuments: [URL: JSONValue]

  public var root: OpenAPILocatedValue {
    OpenAPILocatedValue(value: rawValue, location: .init(sourceURI: sourceURI))
  }

  /// Parses UTF-8 JSON without fetching references or running the meta-schema validator.
  /// JSON syntax errors retain OrderedJSON's byte offset, line, and column.
  public init(
    data: Data, sourceURI: URL? = nil, externalDocuments: [URL: JSONValue] = [:]
  ) throws {
    try self.init(
      rawValue: JSONValue.parse(data), sourceURI: sourceURI, externalDocuments: externalDocuments)
  }

  /// Checks only the object envelope and OpenAPI 3.1 version; checked views are opt-in.
  public init(
    rawValue: JSONValue, sourceURI: URL? = nil, externalDocuments: [URL: JSONValue] = [:]
  ) throws {
    let location = OpenAPISourceLocation(sourceURI: sourceURI)
    for uri in externalDocuments.keys.map({ $0 }) + (sourceURI.map { [$0] } ?? []) {
      guard uri.scheme != nil, uri.fragment == nil else {
        throw OpenAPIImportError(
          location: location,
          message: "Document retrieval URIs must be absolute and fragment-free: \(uri).")
      }
    }
    if let sourceURI, externalDocuments[sourceURI] != nil {
      throw OpenAPIImportError(
        location: location, message: "The source URI must not also identify an external document.")
    }
    let root = OpenAPILocatedValue(value: rawValue, location: location)
    guard let version = try root.string("openapi", required: true) else {
      throw root.error("Missing OpenAPI version.")
    }
    let parts = version.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3, parts[0] == "3", parts[1] == "1",
      !parts[2].isEmpty, parts[2].utf8.allSatisfy({ (48...57).contains($0) })
    else {
      throw OpenAPIImportError(
        location: location.appending("openapi"), message: "Expected an OpenAPI 3.1.x version.")
    }
    self.rawValue = rawValue
    self.sourceURI = sourceURI
    self.externalDocuments = externalDocuments
    self.version = version
  }

  public func encodeJSON(prettyPrinted: Bool = false) throws -> Data {
    try rawValue.serializedData(options: .init(prettyPrinted: prettyPrinted))
  }

  /// Looks up a plain RFC 6901 pointer (not a URI fragment) in the original root.
  public func value(at pointer: String) throws -> OpenAPILocatedValue {
    try Self.lookup(pointer, in: root)
  }

  public func componentSchemas() throws -> [String: OpenAPILocatedValue] {
    guard let components = try root.member("components"),
      let schemas = try components.member("schemas")
    else { return [:] }
    var result: [String: OpenAPILocatedValue] = [:]
    for (name, value) in try schemas.object() {
      result[name] = try OpenAPILocatedValue(
        value: value, location: schemas.location.appending(name)
      ).schema()
    }
    return result
  }

  /// Resolves an OpenAPI Reference Object, never a Schema Object's `$ref`.
  ///
  /// Only root and explicitly supplied documents participate. JSON Pointer fragments
  /// are supported; anchors and cycles are reported. The target is not transplanted
  /// or merged with the source: Reference Object summary/description overrides remain
  /// available on the original value.
  public func resolveReferenceObject(_ source: OpenAPILocatedValue) throws -> OpenAPILocatedValue {
    var node = source
    var visited = Set<OpenAPISourceLocation>()
    while let reference = try node.member("$ref") {
      guard visited.insert(node.location).inserted else {
        throw node.error("Cyclic OpenAPI Reference Object.")
      }
      _ = try node.string("summary")
      _ = try node.string("description")
      node = try resolve(try reference.string(), from: reference)
    }
    _ = try node.object()
    return node
  }

  func resolve(_ reference: String, from source: OpenAPILocatedValue) throws -> OpenAPILocatedValue
  {
    let pieces = reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
    let documentPart = String(pieces[0])
    let fragment = pieces.count == 2 ? String(pieces[1]) : ""
    guard let pointer = fragment.removingPercentEncoding,
      pointer.isEmpty || pointer.hasPrefix("/")
    else {
      throw source.error("Only JSON Pointer reference fragments are supported: \(reference).")
    }

    let targetRoot: OpenAPILocatedValue
    if documentPart.isEmpty {
      if source.location.sourceURI == sourceURI {
        targetRoot = root
      } else if let uri = source.location.sourceURI, let raw = externalDocuments[uri] {
        targetRoot = OpenAPILocatedValue(value: raw, location: .init(sourceURI: uri))
      } else {
        throw source.error("No supplied source document for reference '\(reference)'.")
      }
    } else {
      guard let url = URL(string: documentPart, relativeTo: source.location.sourceURI)?.absoluteURL,
        url.scheme != nil, url.fragment == nil
      else {
        throw source.error(
          "Cannot resolve reference URI '\(reference)' without an absolute base URI.")
      }
      if url == sourceURI {
        targetRoot = root
      } else if let raw = externalDocuments[url] {
        targetRoot = OpenAPILocatedValue(value: raw, location: .init(sourceURI: url))
      } else {
        throw source.error(
          "Reference document was not supplied: \(url). No network loading is performed.")
      }
    }
    do {
      return try Self.lookup(pointer, in: targetRoot)
    } catch let error as OpenAPIImportError {
      throw source.error("Unresolved reference '\(reference)': \(error).")
    }
  }

  static func lookup(_ pointer: String, in root: OpenAPILocatedValue) throws -> OpenAPILocatedValue
  {
    if pointer.isEmpty { return root }
    guard pointer.hasPrefix("/") else {
      throw root.error("Expected an RFC 6901 pointer: \(pointer).")
    }
    var node = root
    for escaped in pointer.dropFirst().split(separator: "/", omittingEmptySubsequences: false) {
      var token = ""
      var iterator = escaped.makeIterator()
      while let character = iterator.next() {
        if character == "~" {
          switch iterator.next() {
          case "0": token.append("~")
          case "1": token.append("/")
          default: throw node.error("Invalid JSON Pointer escape in '\(pointer)'.")
          }
        } else {
          token.append(character)
        }
      }
      let location = node.location.appending(token)
      switch node.value {
      case .object(let object):
        guard let value = object[token] else {
          throw OpenAPIImportError(
            location: location, message: "JSON Pointer member does not exist.")
        }
        node = OpenAPILocatedValue(value: value, location: location)
      case .array(let array):
        guard !token.isEmpty, token.utf8.allSatisfy({ (48...57).contains($0) }),
          token == "0" || !token.hasPrefix("0"),
          let index = Int(token), array.indices.contains(index)
        else {
          throw OpenAPIImportError(location: location, message: "Invalid JSON Pointer array index.")
        }
        node = OpenAPILocatedValue(value: array[index], location: location)
      default: throw node.error("JSON Pointer traverses a scalar.")
      }
    }
    return node
  }
}

extension OpenAPIDocument {
  /// Shares the same raw representation as imported JSON without rebuilding its schemas.
  public func documentRepresentation(sourceURI: URL? = nil) throws -> OpenAPIJSONDocument {
    try OpenAPIJSONDocument(rawValue: jsonValue(), sourceURI: sourceURI)
  }
}
