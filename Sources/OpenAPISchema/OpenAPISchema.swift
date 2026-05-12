import Foundation
import JSONSchema
import JSONSchemaBuilder
import OrderedCollections

typealias JSONObject = OrderedDictionary<String, JSONValue>

public enum OpenAPIVersion: String, Sendable {
  case v3_0_3 = "3.0.3"
  case v3_1_0 = "3.1.0"
}

public enum OpenAPIError: Error, CustomStringConvertible, Equatable {
  case missingInfo
  case duplicateOperationID(String)
  case duplicateComponent(String)
  case duplicatePathOperation(path: String, method: String)
  case missingPathParameter(path: String, parameter: String, operationID: String)
  case unsupportedValidationVersion(OpenAPIVersion)
  case missingResource(String)
  case validationFailed([String])

  public var description: String {
    switch self {
    case .missingInfo:
      return "OpenAPI document requires exactly one Info component."
    case .duplicateOperationID(let operationID):
      return "Duplicate operationId '\(operationID)'."
    case .duplicateComponent(let name):
      return "Duplicate component '\(name)'."
    case .duplicatePathOperation(let path, let method):
      return "Duplicate \(method.uppercased()) operation for path '\(path)'."
    case .missingPathParameter(let path, let parameter, let operationID):
      return
        "Path '\(path)' contains '{\(parameter)}' but operation '\(operationID)' does not document it."
    case .unsupportedValidationVersion(let version):
      return "OpenAPI \(version.rawValue) validation is not bundled yet."
    case .missingResource(let name):
      return "Missing bundled resource '\(name)'."
    case .validationFailed(let errors):
      return "OpenAPI validation failed: \(errors.joined(separator: "; "))"
    }
  }
}

@resultBuilder
public enum OpenAPIDocumentBuilder {
  public static func buildExpression(_ component: any OpenAPIDocumentComponent)
    -> [any OpenAPIDocumentComponent]
  {
    [component]
  }

  public static func buildBlock(_ components: [any OpenAPIDocumentComponent]...)
    -> [any OpenAPIDocumentComponent]
  {
    components.flatMap { $0 }
  }

  public static func buildArray(_ components: [[any OpenAPIDocumentComponent]])
    -> [any OpenAPIDocumentComponent]
  {
    components.flatMap { $0 }
  }

  public static func buildOptional(_ components: [any OpenAPIDocumentComponent]?)
    -> [any OpenAPIDocumentComponent]
  {
    components ?? []
  }

  public static func buildEither(first components: [any OpenAPIDocumentComponent])
    -> [any OpenAPIDocumentComponent]
  {
    components
  }

  public static func buildEither(second components: [any OpenAPIDocumentComponent])
    -> [any OpenAPIDocumentComponent]
  {
    components
  }
}

public protocol OpenAPIDocumentComponent: Sendable {
  func apply(to document: inout OpenAPIDocument)
}

public struct OpenAPIDocument: Sendable {
  public let version: OpenAPIVersion
  private var info: Info?
  private var servers: [Server] = []
  private var paths: [Path] = []
  private var components = Components()

  public init(
    _ version: OpenAPIVersion = .v3_1_0,
    @OpenAPIDocumentBuilder content: () -> [any OpenAPIDocumentComponent]
  ) {
    self.version = version
    for component in content() {
      component.apply(to: &self)
    }
  }

  mutating func setInfo(_ info: Info) {
    self.info = info
  }

  mutating func appendServer(_ server: Server) {
    servers.append(server)
  }

  mutating func appendPath(_ path: Path) {
    paths.append(path)
  }

  mutating func mergeComponents(_ components: Components) {
    self.components.merge(components)
  }

  public func jsonValue() throws -> JSONValue {
    guard let info else {
      throw OpenAPIError.missingInfo
    }

    var seenOperationIDs = Set<String>()
    var pathObject = JSONObject()
    for path in paths {
      var item = pathObject[path.path]?.object ?? [:]
      for operation in path.operations {
        if !seenOperationIDs.insert(operation.operationID).inserted {
          throw OpenAPIError.duplicateOperationID(operation.operationID)
        }
        if item[operation.method.rawValue] != nil {
          throw OpenAPIError.duplicatePathOperation(
            path: path.path, method: operation.method.rawValue)
        }
        try operation.validatePathParameters(for: path.path)
        item[operation.method.rawValue] = try operation.jsonValue()
      }
      pathObject[path.path] = .object(item)
    }

    var object: JSONObject = [
      "openapi": .string(version.rawValue),
      "info": info.jsonValue(),
      "paths": .object(pathObject),
    ]
    if !servers.isEmpty {
      object["servers"] = .array(servers.map { $0.jsonValue() })
    }
    let componentsValue = try components.jsonValue()
    if case .object(let values) = componentsValue, !values.isEmpty {
      object["components"] = componentsValue
    }
    return .object(object)
  }

  public func encodeCanonicalJSON(prettyPrinted: Bool = true) throws -> Data {
    var data = try jsonValue().serializedData(
      options: JSONValue.SerializationOptions(prettyPrinted: prettyPrinted))
    if data.last != UInt8(ascii: "\n") {
      data.append(UInt8(ascii: "\n"))
    }
    return data
  }

  public func validate() throws -> ValidationResult {
    try OpenAPIValidator.validate(self)
  }
}

public struct Info: OpenAPIDocumentComponent {
  public var title: String
  public var version: String
  public var description: String?

  public init(title: String, version: String, description: String? = nil) {
    self.title = title
    self.version = version
    self.description = description
  }

  public func apply(to document: inout OpenAPIDocument) {
    document.setInfo(self)
  }

  func jsonValue() -> JSONValue {
    var object: JSONObject = [
      "title": .string(title),
      "version": .string(version),
    ]
    if let description {
      object["description"] = .string(description)
    }
    return .object(object)
  }
}

public struct Server: OpenAPIDocumentComponent {
  public var url: String
  public var description: String?

  public init(_ url: String, description: String? = nil) {
    self.url = url
    self.description = description
  }

  public func apply(to document: inout OpenAPIDocument) {
    document.appendServer(self)
  }

  func jsonValue() -> JSONValue {
    var object: JSONObject = ["url": .string(url)]
    if let description {
      object["description"] = .string(description)
    }
    return .object(object)
  }
}

@resultBuilder
public enum ComponentsBuilder {
  public static func buildExpression(_ component: any ComponentsComponent)
    -> [any ComponentsComponent]
  {
    [component]
  }

  public static func buildBlock(_ components: [any ComponentsComponent]...)
    -> [any ComponentsComponent]
  {
    components.flatMap { $0 }
  }

  public static func buildArray(_ components: [[any ComponentsComponent]])
    -> [any ComponentsComponent]
  {
    components.flatMap { $0 }
  }

  public static func buildOptional(_ components: [any ComponentsComponent]?)
    -> [any ComponentsComponent]
  {
    components ?? []
  }
}

public protocol ComponentsComponent: Sendable {
  func apply(to components: inout Components)
}

public struct Components: OpenAPIDocumentComponent, Sendable {
  private var schemas: [Schema] = []
  private var securitySchemes: [SecurityScheme] = []

  public init(@ComponentsBuilder content: () -> [any ComponentsComponent] = { [] }) {
    for component in content() {
      component.apply(to: &self)
    }
  }

  public func apply(to document: inout OpenAPIDocument) {
    document.mergeComponents(self)
  }

  mutating func appendSchema(_ schema: Schema) {
    schemas.append(schema)
  }

  mutating func appendSecurityScheme(_ scheme: SecurityScheme) {
    securitySchemes.append(scheme)
  }

  mutating func merge(_ other: Components) {
    schemas.append(contentsOf: other.schemas)
    securitySchemes.append(contentsOf: other.securitySchemes)
  }

  func jsonValue() throws -> JSONValue {
    var object = JSONObject()
    if !schemas.isEmpty {
      var schemaObject = JSONObject()
      for schema in schemas {
        if schemaObject[schema.name] != nil {
          throw OpenAPIError.duplicateComponent(schema.name)
        }
        schemaObject[schema.name] = try schema.schema()
      }
      object["schemas"] = .object(schemaObject)
    }
    if !securitySchemes.isEmpty {
      var securityObject = JSONObject()
      for scheme in securitySchemes {
        if securityObject[scheme.name] != nil {
          throw OpenAPIError.duplicateComponent(scheme.name)
        }
        securityObject[scheme.name] = scheme.jsonValue()
      }
      object["securitySchemes"] = .object(securityObject)
    }
    return .object(object)
  }
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
private func defaultComponentName<T: Schemable>(for type: T.Type) -> String {
  SchemaAnchorName.sanitized(String(describing: type))
}

public struct Schema: ComponentsComponent, @unchecked Sendable {
  public let name: String
  private let provider: () throws -> JSONValue

  public init(_ name: String, raw: JSONValue) {
    self.name = name
    self.provider = { raw }
  }

  @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  public init<T: Schemable>(_ type: T.Type, name: String? = nil) {
    self.name = name ?? defaultComponentName(for: type)
    self.provider = {
      T.schema.definition().jsonValue
    }
  }

  public func apply(to components: inout Components) {
    components.appendSchema(self)
  }

  func schema() throws -> JSONValue {
    try provider()
  }
}

public struct SecurityScheme: ComponentsComponent {
  public let name: String
  private let value: JSONValue

  public init(name: String, value: JSONValue) {
    self.name = name
    self.value = value
  }

  public func apply(to components: inout Components) {
    components.appendSecurityScheme(self)
  }

  func jsonValue() -> JSONValue {
    value
  }
}

public func BearerAuth(_ name: String, bearerFormat: String? = nil) -> SecurityScheme {
  var value: JSONObject = [
    "type": .string("http"),
    "scheme": .string("bearer"),
  ]
  if let bearerFormat {
    value["bearerFormat"] = .string(bearerFormat)
  }
  return SecurityScheme(name: name, value: .object(value))
}

public func APIKeyAuth(_ name: String, in location: ParameterLocation, keyName: String)
  -> SecurityScheme
{
  SecurityScheme(
    name: name,
    value: .object([
      "type": .string("apiKey"),
      "in": .string(location.rawValue),
      "name": .string(keyName),
    ])
  )
}

@resultBuilder
public enum PathBuilder {
  public static func buildExpression(_ operation: Operation) -> [Operation] {
    [operation]
  }

  public static func buildBlock(_ operations: [Operation]...) -> [Operation] {
    operations.flatMap { $0 }
  }

  public static func buildArray(_ operations: [[Operation]]) -> [Operation] {
    operations.flatMap { $0 }
  }

  public static func buildOptional(_ operations: [Operation]?) -> [Operation] {
    operations ?? []
  }
}

public struct Path: OpenAPIDocumentComponent {
  public let path: String
  public let operations: [Operation]

  public init(_ path: String, @PathBuilder operations: () -> [Operation]) {
    self.path = path
    self.operations = operations()
  }

  public func apply(to document: inout OpenAPIDocument) {
    document.appendPath(self)
  }
}

public enum HTTPMethod: String, Sendable {
  case get
  case put
  case post
  case delete
  case patch
  case options
  case head
  case trace
}

@resultBuilder
public enum OperationBuilder {
  public static func buildExpression(_ component: any OperationComponent)
    -> [any OperationComponent]
  {
    [component]
  }

  public static func buildBlock(_ components: [any OperationComponent]...)
    -> [any OperationComponent]
  {
    components.flatMap { $0 }
  }

  public static func buildArray(_ components: [[any OperationComponent]])
    -> [any OperationComponent]
  {
    components.flatMap { $0 }
  }

  public static func buildOptional(_ components: [any OperationComponent]?)
    -> [any OperationComponent]
  {
    components ?? []
  }
}

public protocol OperationComponent: Sendable {
  func apply(to operation: inout Operation)
}

public struct Operation: Sendable {
  public let method: HTTPMethod
  public let operationID: String
  private var tags: [String] = []
  private var summary: String?
  private var description: String?
  private var parameters: [Parameter] = []
  private var requestBodies: [Body] = []
  private var responses: [Response] = []
  private var security: [SecurityRequirement] = []

  public init(
    method: HTTPMethod,
    operationID: String,
    @OperationBuilder content: () -> [any OperationComponent]
  ) {
    self.method = method
    self.operationID = operationID
    for component in content() {
      component.apply(to: &self)
    }
  }

  mutating func appendTags(_ tags: [String]) {
    self.tags.append(contentsOf: tags)
  }

  mutating func setSummary(_ summary: String) {
    self.summary = summary
  }

  mutating func setDescription(_ description: String) {
    self.description = description
  }

  mutating func appendParameter(_ parameter: Parameter) {
    parameters.append(parameter)
  }

  mutating func appendRequestBodies(_ bodies: [Body]) {
    requestBodies.append(contentsOf: bodies)
  }

  mutating func appendResponse(_ response: Response) {
    responses.append(response)
  }

  mutating func appendSecurity(_ requirement: SecurityRequirement) {
    security.append(requirement)
  }

  func jsonValue() throws -> JSONValue {
    var object: JSONObject = [
      "operationId": .string(operationID)
    ]
    if !tags.isEmpty {
      object["tags"] = .array(tags.map(JSONValue.string))
    }
    if let summary {
      object["summary"] = .string(summary)
    }
    if let description {
      object["description"] = .string(description)
    }
    if !parameters.isEmpty {
      object["parameters"] = .array(parameters.map { $0.jsonValue() })
    }
    if !requestBodies.isEmpty {
      object["requestBody"] = requestBodyJSON(requestBodies)
    }

    var responseObject = JSONObject()
    for response in responses.isEmpty ? [Response(.default)] : responses {
      responseObject[response.status.rawValue] = try response.jsonValue()
    }
    object["responses"] = .object(responseObject)

    if !security.isEmpty {
      object["security"] = .array(security.map { $0.jsonValue() })
    }
    return .object(object)
  }

  func validatePathParameters(for path: String) throws {
    let names = Self.pathParameterNames(in: path)
    guard !names.isEmpty else { return }
    let documented = Set(parameters.filter { $0.location == .path }.map(\.name))
    for name in names where !documented.contains(name) {
      throw OpenAPIError.missingPathParameter(path: path, parameter: name, operationID: operationID)
    }
  }

  private static func pathParameterNames(in path: String) -> [String] {
    var names: [String] = []
    var remainder = path[...]
    while let open = remainder.firstIndex(of: "{"),
      let close = remainder[open...].firstIndex(of: "}")
    {
      let nameStart = remainder.index(after: open)
      if nameStart < close {
        names.append(String(remainder[nameStart..<close]))
      }
      remainder = remainder[remainder.index(after: close)...]
    }
    return names
  }

  private func requestBodyJSON(_ bodies: [Body]) -> JSONValue {
    .object([
      "required": .boolean(true),
      "content": contentJSON(bodies),
    ])
  }
}

public func GET(
  operationID: String,
  @OperationBuilder content: () -> [any OperationComponent]
) -> Operation {
  Operation(method: .get, operationID: operationID, content: content)
}

public func POST(
  operationID: String,
  @OperationBuilder content: () -> [any OperationComponent]
) -> Operation {
  Operation(method: .post, operationID: operationID, content: content)
}

public func PUT(
  operationID: String,
  @OperationBuilder content: () -> [any OperationComponent]
) -> Operation {
  Operation(method: .put, operationID: operationID, content: content)
}

public func PATCH(
  operationID: String,
  @OperationBuilder content: () -> [any OperationComponent]
) -> Operation {
  Operation(method: .patch, operationID: operationID, content: content)
}

public func DELETE(
  operationID: String,
  @OperationBuilder content: () -> [any OperationComponent]
) -> Operation {
  Operation(method: .delete, operationID: operationID, content: content)
}

public struct Tags: OperationComponent {
  private let values: [String]

  public init(_ values: String...) {
    self.values = values
  }

  public func apply(to operation: inout Operation) {
    operation.appendTags(values)
  }
}

public struct Summary: OperationComponent {
  private let value: String

  public init(_ value: String) {
    self.value = value
  }

  public func apply(to operation: inout Operation) {
    operation.setSummary(value)
  }
}

public struct Description: OperationComponent {
  private let value: String

  public init(_ value: String) {
    self.value = value
  }

  public func apply(to operation: inout Operation) {
    operation.setDescription(value)
  }
}

public enum ParameterLocation: String, Sendable {
  case path
  case query
  case header
  case cookie
}

public struct Parameter: OperationComponent, Sendable {
  public let name: String
  public let location: ParameterLocation
  public let schema: OpenAPISchemaValue
  public let required: Bool
  public let description: String?

  public init(
    _ name: String,
    in location: ParameterLocation,
    schema: OpenAPISchemaValue = .string(),
    required: Bool? = nil,
    description: String? = nil
  ) {
    self.name = name
    self.location = location
    self.schema = schema
    self.required = required ?? (location == .path)
    self.description = description
  }

  public func apply(to operation: inout Operation) {
    operation.appendParameter(self)
  }

  func jsonValue() -> JSONValue {
    var object: JSONObject = [
      "name": .string(name),
      "in": .string(location.rawValue),
      "required": .boolean(required),
      "schema": schema.jsonValue(),
    ]
    if let description {
      object["description"] = .string(description)
    }
    return .object(object)
  }
}

public func PathParameter(
  _ name: String,
  schema: OpenAPISchemaValue = .string(),
  description: String? = nil
) -> Parameter {
  Parameter(name, in: .path, schema: schema, required: true, description: description)
}

public func QueryParameter(
  _ name: String,
  schema: OpenAPISchemaValue = .string(),
  required: Bool = false,
  description: String? = nil
) -> Parameter {
  Parameter(name, in: .query, schema: schema, required: required, description: description)
}

@resultBuilder
public enum BodyBuilder {
  public static func buildExpression(_ body: Body) -> [Body] {
    [body]
  }

  public static func buildBlock(_ bodies: [Body]...) -> [Body] {
    bodies.flatMap { $0 }
  }

  public static func buildArray(_ bodies: [[Body]]) -> [Body] {
    bodies.flatMap { $0 }
  }

  public static func buildOptional(_ bodies: [Body]?) -> [Body] {
    bodies ?? []
  }
}

public struct Request: OperationComponent {
  private let bodies: [Body]

  public init(@BodyBuilder bodies: () -> [Body]) {
    self.bodies = bodies()
  }

  public func apply(to operation: inout Operation) {
    operation.appendRequestBodies(bodies)
  }
}

public struct Response: OperationComponent, Sendable {
  public let status: HTTPStatus
  public let description: String
  private let bodies: [Body]

  public init(
    _ status: HTTPStatus,
    description: String? = nil,
    @BodyBuilder bodies: () -> [Body] = { [] }
  ) {
    self.status = status
    self.description = description ?? status.defaultDescription
    self.bodies = bodies()
  }

  public func apply(to operation: inout Operation) {
    operation.appendResponse(self)
  }

  func jsonValue() throws -> JSONValue {
    var object: JSONObject = [
      "description": .string(description)
    ]
    if !bodies.isEmpty {
      object["content"] = contentJSON(bodies)
    }
    return .object(object)
  }
}

public struct Body: Sendable {
  public let mediaType: MediaType
  public let schema: OpenAPISchemaValue

  public init(_ mediaType: MediaType, schema: OpenAPISchemaValue) {
    self.mediaType = mediaType
    self.schema = schema
  }
}

public func JSONBody(_ componentName: String) -> Body {
  Body(.json, schema: .component(componentName))
}

@available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
public func JSONBody<T: Schemable>(_ type: T.Type, name: String? = nil) -> Body {
  Body(.json, schema: .component(type, name: name))
}

public func JSONBody(schema: OpenAPISchemaValue) -> Body {
  Body(.json, schema: schema)
}

func contentJSON(_ bodies: [Body]) -> JSONValue {
  var content = JSONObject()
  for body in bodies {
    content[body.mediaType.rawValue] = .object([
      "schema": body.schema.jsonValue()
    ])
  }
  return .object(content)
}

public struct MediaType: RawRepresentable, ExpressibleByStringLiteral, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(stringLiteral value: String) {
    self.rawValue = value
  }

  public static let json: MediaType = "application/json"
  public static let octetStream: MediaType = "application/octet-stream"
  public static let textPlain: MediaType = "text/plain"
}

public struct HTTPStatus: RawRepresentable, ExpressibleByIntegerLiteral, Hashable, Sendable {
  public let rawValue: String

  public init(rawValue: String) {
    self.rawValue = rawValue
  }

  public init(integerLiteral value: Int) {
    self.rawValue = String(value)
  }

  public static let `default` = HTTPStatus(rawValue: "default")
  public static let ok: HTTPStatus = 200
  public static let created: HTTPStatus = 201
  public static let accepted: HTTPStatus = 202
  public static let noContent: HTTPStatus = 204
  public static let badRequest: HTTPStatus = 400
  public static let unauthorized: HTTPStatus = 401
  public static let forbidden: HTTPStatus = 403
  public static let notFound: HTTPStatus = 404
  public static let conflict: HTTPStatus = 409
  public static let unprocessableContent: HTTPStatus = 422
  public static let internalServerError: HTTPStatus = 500

  var defaultDescription: String {
    switch rawValue {
    case "200": "OK"
    case "201": "Created"
    case "202": "Accepted"
    case "204": "No Content"
    case "400": "Bad Request"
    case "401": "Unauthorized"
    case "403": "Forbidden"
    case "404": "Not Found"
    case "409": "Conflict"
    case "422": "Unprocessable Content"
    case "500": "Internal Server Error"
    case "default": "Default response"
    default: "HTTP \(rawValue)"
    }
  }
}

public struct SecurityRequirement: OperationComponent {
  public let schemeName: String
  public let scopes: [String]

  public init(_ schemeName: String, scopes: [String] = []) {
    self.schemeName = schemeName
    self.scopes = scopes
  }

  public func apply(to operation: inout Operation) {
    operation.appendSecurity(self)
  }

  func jsonValue() -> JSONValue {
    .object([schemeName: .array(scopes.map(JSONValue.string))])
  }
}

public func Security(_ schemeName: String, scopes: [String] = []) -> SecurityRequirement {
  SecurityRequirement(schemeName, scopes: scopes)
}

public indirect enum OpenAPISchemaValue: Sendable {
  case raw(JSONValue)
  case component(String)
  case array(OpenAPISchemaValue)
  case object(properties: [String: OpenAPISchemaValue], required: [String])
  case string(format: String? = nil)
  case integer(format: String? = nil)
  case number(format: String? = nil)
  case boolean
  case binaryString

  public static func rawObject(_ object: [String: JSONValue]) -> Self {
    .raw(.object(JSONObject(uniqueKeysWithValues: object.map { ($0.key, $0.value) })))
  }

  @available(macOS 14.0, iOS 17.0, watchOS 10.0, tvOS 17.0, *)
  public static func component<T: Schemable>(_ type: T.Type, name: String? = nil) -> Self {
    .component(name ?? defaultComponentName(for: type))
  }

  public func jsonValue() -> JSONValue {
    switch self {
    case .raw(let value):
      return value
    case .component(let name):
      return .object(["$ref": .string("#/components/schemas/\(name)")])
    case .array(let items):
      return .object([
        "type": .string("array"),
        "items": items.jsonValue(),
      ])
    case .object(let properties, let required):
      var propertyObject = JSONObject()
      for (name, schema) in properties {
        propertyObject[name] = schema.jsonValue()
      }
      var object: JSONObject = [
        "type": .string("object"),
        "properties": .object(propertyObject),
      ]
      if !required.isEmpty {
        object["required"] = .array(required.map(JSONValue.string))
      }
      return .object(object)
    case .string(let format):
      var object: JSONObject = ["type": .string("string")]
      if let format {
        object["format"] = .string(format)
      }
      return .object(object)
    case .integer(let format):
      var object: JSONObject = ["type": .string("integer")]
      if let format {
        object["format"] = .string(format)
      }
      return .object(object)
    case .number(let format):
      var object: JSONObject = ["type": .string("number")]
      if let format {
        object["format"] = .string(format)
      }
      return .object(object)
    case .boolean:
      return .object(["type": .string("boolean")])
    case .binaryString:
      return .object([
        "type": .string("string"),
        "format": .string("binary"),
      ])
    }
  }
}
