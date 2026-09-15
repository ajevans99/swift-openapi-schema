import OrderedJSON

public struct OpenAPIMediaTypeView: Sendable {
  public let mediaType: String
  public let source: OpenAPILocatedValue
  public let schema: OpenAPILocatedValue?
}

public struct OpenAPIParameterView: Sendable {
  public let name: String
  /// The OpenAPI `in` value, not the source JSON Pointer.
  public let location: String
  public let required: Bool
  public let source: OpenAPILocatedValue
  public let target: OpenAPILocatedValue
  public let schema: OpenAPILocatedValue?
  public let content: [OpenAPIMediaTypeView]
}

public struct OpenAPIRequestBodyView: Sendable {
  public let required: Bool
  public let source: OpenAPILocatedValue
  public let target: OpenAPILocatedValue
  public let content: [OpenAPIMediaTypeView]
}

public struct OpenAPIResponseView: Sendable {
  /// An exact status code, uppercase range (for example `2XX`), or `default`.
  public let status: String
  public let source: OpenAPILocatedValue
  public let target: OpenAPILocatedValue
  public let content: [OpenAPIMediaTypeView]
}

public struct OpenAPIOperationView: Sendable {
  public let operationID: String?
  public let method: String
  public let path: String
  public let source: OpenAPILocatedValue
  public let pathItem: OpenAPILocatedValue
  /// Effective declarations, closest scope first. An absent declaration yields [].
  /// No synthetic default server is inserted; raw scopes distinguish absent and empty.
  public let servers: [OpenAPILocatedValue]
  public let parameters: [OpenAPIParameterView]
  public let requestBody: OpenAPIRequestBodyView?
  public let responses: [OpenAPIResponseView]
  /// Effective OR alternatives; each object retains its AND-ed schemes/scopes.
  public let security: [OpenAPILocatedValue]
}

extension OpenAPIJSONDocument {
  /// Checks and enumerates `paths` operations in declaration order.
  ///
  /// Fails at the first malformed consumed shape or unsupported reference. Callbacks,
  /// webhooks, and all other unmodeled fields remain available in the raw document.
  /// This is not full OpenAPI validation or a JSON Schema compilation step.
  public func operations() throws -> [OpenAPIOperationView] {
    let documentServers = try checkedServers(in: root)
    let documentSecurity = try checkedSecurity(in: root)
    guard let paths = try root.member("paths") else { return [] }
    var operations: [OpenAPIOperationView] = []
    var operationIDs = Set<String>()
    let methods: Set<String> = [
      "get", "put", "post", "delete", "options", "head", "patch", "trace",
    ]
    for (path, raw) in try paths.object() where !path.hasPrefix("x-") {
      let original = OpenAPILocatedValue(value: raw, location: paths.location.appending(path))
      guard path.hasPrefix("/") else { throw original.error("Path keys must begin with '/'.") }
      let item = try resolvePathItem(original)
      let pathServers = try checkedServers(in: item)
      let inherited = try checkedParameters(in: item)
      for (method, rawOperation) in try item.object() where methods.contains(method) {
        let operation = OpenAPILocatedValue(
          value: rawOperation, location: item.location.appending(method))
        _ = try operation.object()
        let operationID = try operation.string("operationId")
        if let operationID, !operationIDs.insert(operationID).inserted {
          throw operation.error("Duplicate operationId '\(operationID)'.")
        }
        let ownParameters = try checkedParameters(in: operation)
        var parameters = inherited
        for parameter in ownParameters {
          if let index = parameters.firstIndex(where: {
            $0.name == parameter.name && $0.location == parameter.location
          }) {
            parameters[index] = parameter
          } else {
            parameters.append(parameter)
          }
        }
        let servers = try checkedServers(in: operation) ?? pathServers ?? documentServers ?? []
        let security = try checkedSecurity(in: operation) ?? documentSecurity ?? []
        var body: OpenAPIRequestBodyView?
        if let source = try operation.member("requestBody") {
          let target = try resolveReferenceObject(source)
          body = OpenAPIRequestBodyView(
            required: try target.boolean("required"), source: source, target: target,
            content: try checkedContent(in: target, required: true))
        }
        operations.append(
          OpenAPIOperationView(
            operationID: operationID, method: method, path: path, source: operation,
            pathItem: original, servers: servers, parameters: parameters, requestBody: body,
            responses: try checkedResponses(in: operation), security: security))
      }
    }
    return operations
  }

  private func resolvePathItem(_ source: OpenAPILocatedValue) throws -> OpenAPILocatedValue {
    var node = source
    var seen = Set<OpenAPISourceLocation>()
    while let ref = try node.member("$ref") {
      guard seen.insert(node.location).inserted else {
        throw ref.error("Cyclic Path Item reference.")
      }
      // OAS leaves conflicting Path Item fields undefined. Do not invent a merge.
      guard try node.object().keys.allSatisfy({ $0 == "$ref" || $0.hasPrefix("x-") }) else {
        throw ref.error("Path Item $ref with sibling fields is unsupported; merging is ambiguous.")
      }
      node = try resolve(try ref.string(), from: ref)
    }
    _ = try node.object()
    return node
  }

  private func checkedParameters(in parent: OpenAPILocatedValue) throws -> [OpenAPIParameterView] {
    guard let list = try parent.member("parameters") else { return [] }
    var result: [OpenAPIParameterView] = []
    for source in try list.elements() {
      let target = try resolveReferenceObject(source)
      guard let name = try target.string("name", required: true),
        let location = try target.string("in", required: true)
      else { throw target.error("Parameter name and in are required.") }
      guard ["query", "header", "path", "cookie"].contains(location) else {
        throw target.error("Unsupported parameter location '\(location)'.")
      }
      let required = try target.boolean("required")
      if location == "path" && !required {
        throw target.error("Path parameters must have required: true.")
      }
      if result.contains(where: { $0.name == name && $0.location == location }) {
        throw source.error("Duplicate parameter identity ('\(name)', '\(location)') in one scope.")
      }
      let schema = try target.member("schema")?.schema()
      let content = try checkedContent(in: target)
      guard (schema != nil) != (try target.member("content") != nil) else {
        throw target.error("A parameter must contain exactly one of schema or content.")
      }
      if schema == nil && content.count != 1 {
        throw target.error("Parameter content must contain exactly one media type.")
      }
      result.append(
        OpenAPIParameterView(
          name: name, location: location, required: required, source: source,
          target: target, schema: schema, content: content))
    }
    return result
  }

  private func checkedContent(
    in parent: OpenAPILocatedValue, required: Bool = false
  ) throws -> [OpenAPIMediaTypeView] {
    guard let content = try parent.member("content") else {
      if required { throw parent.error("Request Body content is required.") }
      return []
    }
    var result: [OpenAPIMediaTypeView] = []
    for (mediaType, value) in try content.object() {
      let node = OpenAPILocatedValue(value: value, location: content.location.appending(mediaType))
      _ = try node.object()
      result.append(
        OpenAPIMediaTypeView(
          mediaType: mediaType, source: node, schema: try node.member("schema")?.schema()))
    }
    return result
  }

  private func checkedResponses(in operation: OpenAPILocatedValue) throws -> [OpenAPIResponseView] {
    guard let responses = try operation.member("responses") else {
      throw operation.error("Operation responses are required.")
    }
    var result: [OpenAPIResponseView] = []
    for (status, value) in try responses.object() where !status.hasPrefix("x-") {
      let source = OpenAPILocatedValue(value: value, location: responses.location.appending(status))
      let bytes = Array(status.utf8)
      let validCode =
        bytes.count == 3 && (49...53).contains(bytes[0])
        && ((bytes[1] == 88 && bytes[2] == 88)
          || ((48...57).contains(bytes[1]) && (48...57).contains(bytes[2])))
      guard status == "default" || validCode else {
        throw source.error("Expected a response status code, range, or default.")
      }
      let target = try resolveReferenceObject(source)
      _ = try target.string("description", required: true)
      result.append(
        OpenAPIResponseView(
          status: status, source: source, target: target, content: try checkedContent(in: target)))
    }
    guard !result.isEmpty else { throw responses.error("At least one response is required.") }
    return result
  }

  private func checkedServers(in parent: OpenAPILocatedValue) throws -> [OpenAPILocatedValue]? {
    guard let node = try parent.member("servers") else { return nil }
    let servers = try node.elements()
    for server in servers {
      _ = try server.string("url", required: true)
      if let variables = try server.member("variables") {
        for (name, raw) in try variables.object() {
          let variable = OpenAPILocatedValue(
            value: raw, location: variables.location.appending(name))
          _ = try variable.string("default", required: true)
          if let choices = try variable.member("enum") {
            let values = try choices.elements()
            guard !values.isEmpty else {
              throw choices.error("Server variable enum must not be empty.")
            }
            for value in values { _ = try value.string() }
          }
        }
      }
    }
    return servers
  }

  private func checkedSecurity(in parent: OpenAPILocatedValue) throws -> [OpenAPILocatedValue]? {
    guard let node = try parent.member("security") else { return nil }
    let alternatives = try node.elements()
    for alternative in alternatives {
      for (scheme, value) in try alternative.object() {
        let scopes = OpenAPILocatedValue(
          value: value, location: alternative.location.appending(scheme))
        for scope in try scopes.elements() { _ = try scope.string() }
      }
    }
    return alternatives
  }
}
