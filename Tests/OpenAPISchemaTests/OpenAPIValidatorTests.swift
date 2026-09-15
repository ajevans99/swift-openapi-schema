import Foundation
import JSONSchema
import Testing

@testable import OpenAPISchema

struct OpenAPIValidatorTests {
  @Test
  func authoredAndImportedValidationAgree() throws {
    let authored = OpenAPIDocument(.v3_1_0) {
      Info(title: "Authored API", version: "1")
    }
    let imported = try OpenAPIJSONDocument(data: authored.encodeCanonicalJSON())
    #expect(try OpenAPIValidator.validate(authored).isValid)
    #expect(try OpenAPIValidator.validate(imported).isValid)
    #expect(try imported.validate().isValid)
    try OpenAPIValidator.assertValid(authored)
    try OpenAPIValidator.assertValid(imported)
  }

  @Test
  func authoredOpenAPI30StillFailsWithUnsupportedVersion() {
    let document = OpenAPIDocument(.v3_0_3) {}
    #expect(throws: OpenAPIError.unsupportedValidationVersion(.v3_0_3)) {
      try OpenAPIValidator.validate(document)
    }
    #expect(throws: OpenAPIError.unsupportedValidationVersion(.v3_0_3)) {
      try OpenAPIValidator.assertValid(document)
    }
    #expect(throws: OpenAPIError.unsupportedValidationVersion(.v3_0_3)) {
      try document.validate()
    }
  }

  @Test
  func strictMinimalImportedDocument() throws {
    let document = try OpenAPIJSONDocument(rawValue: [
      "openapi": "3.1.1",
      "info": ["title": "Imported API", "version": "1"],
      "paths": [:],
    ])
    let result = try document.validate()
    #expect(result.isValid)
    #expect(result.evaluationErrors?.isEmpty != false)
  }

  @Test
  func strictParameterWithStyle() throws {
    let document = try OpenAPIJSONDocument(rawValue: [
      "openapi": "3.1.0",
      "info": ["title": "Imported API", "version": "1"],
      "paths": [
        "/pets/{id}": [
          "get": [
            "parameters": [
              [
                "name": "id", "in": "path", "required": true, "style": "simple",
                "schema": ["type": "string"],
              ]
            ],
            "responses": ["200": ["description": "OK"]],
          ]
        ]
      ],
    ])
    let result = try document.validate()
    #expect(result.isValid)
    #expect(result.evaluationErrors?.isEmpty != false)
  }

  @Test(arguments: ["non-oauth-scopes", "webhook-example"])
  func officialImportedExamples(name: String) throws {
    let document = try OpenAPIJSONDocument(
      data: resourceData("openapi-3.1-example-\(name)"),
      sourceURI: URL(string: "https://example.invalid/\(name).json"))
    let result = try document.validate()
    #expect(result.isValid)
    #expect(result.evaluationErrors?.isEmpty != false)
    try OpenAPIValidator.assertValid(document)
  }

  @Test(arguments: ["identifier", "url"])
  func validLicenseAndSpecificationExtensions(field: String) throws {
    let license: JSONValue =
      field == "identifier"
      ? ["name": "MIT", "identifier": "MIT", "x-license": true]
      : ["name": "MIT", "url": "https://example.com/license", "x-license": true]
    let document = try OpenAPIJSONDocument(rawValue: [
      "openapi": "3.1.2",
      "info": ["title": "API", "version": "1", "license": license, "x-info": true],
      "paths": [:],
      "x-document": ["custom": true],
    ])
    #expect(try document.validate().isValid)
  }

  @Test(arguments: ["unknown-root", "unknown-info", "license", "parameter-style"])
  func strictRejectsPreviouslyAcceptedStructures(name: String) throws {
    var value: JSONValue = [
      "openapi": "3.1.0",
      "info": ["title": "Invalid API", "version": "1"],
      "paths": [:],
    ]
    var root = try #require(value.object)
    switch name {
    case "unknown-root":
      root["unexpected"] = true
    case "unknown-info":
      root["info"] = ["title": "API", "version": "1", "unexpected": true]
    case "license":
      root["info"] = [
        "title": "API", "version": "1",
        "license": ["name": "MIT", "identifier": "MIT", "url": "https://example.com/license"],
      ]
    default:
      root["components"] = [
        "parameters": [
          "id": [
            "name": "id", "in": "path", "required": true, "style": "form",
            "schema": ["type": "string"],
          ]
        ]
      ]
    }
    value = .object(root)
    let document = try OpenAPIJSONDocument(rawValue: value)
    let strict = try document.validate()
    let legacy = try legacyStrippedSchema().validate(value)
    #expect(!strict.isValid)
    #expect(legacy.isValid)
    #expect(strict.evaluationErrors?.isEmpty != false)
    let keyword = name.hasPrefix("unknown") ? "unevaluatedProperties" : "dependentSchemas"
    let location: String
    switch name {
    case "unknown-root": location = "#"
    case "unknown-info": location = "#/info"
    case "license": location = "#/info/license"
    default: location = "#/components/parameters/id"
    }
    #expect(
      allErrors(strict.errors ?? []).contains {
        $0.keyword == keyword && $0.instanceLocation.description == location
      })
    do {
      try OpenAPIValidator.assertValid(document)
      Issue.record("Expected structural validation to fail.")
    } catch OpenAPIError.validationFailed(let messages) {
      #expect(messages.contains { $0.contains("\(keyword) at \(location)") })
      #expect(messages.contains { $0.contains("(schema #/") })
    }
  }

  @Test
  func parsingDoesNotPerformStructuralValidation() throws {
    let document = try OpenAPIJSONDocument(data: Data(#"{"openapi":"3.1.0"}"#.utf8))
    #expect(try !document.validate().isValid)
  }

  @Test
  func schemaObjectsRemainOpaqueAndReferencesAreNotFetched() throws {
    let raw: JSONValue = [
      "openapi": "3.1.0",
      "info": ["title": "Opaque schemas", "version": "1"],
      "jsonSchemaDialect": "https://example.invalid/custom-dialect",
      "components": [
        "schemas": [
          "Opaque": [
            "$id": "relative-schema",
            "$schema": "https://example.invalid/another-dialect",
            "$ref": "https://example.invalid/not-supplied.json#/$defs/missing",
            "type": 17,
            "x-custom-keyword": ["anything": true],
          ],
          "Boolean": false,
        ],
        "responses": [
          "Remote": ["$ref": "https://example.invalid/not-supplied-response.json"]
        ],
      ],
    ]
    let document = try OpenAPIJSONDocument(
      rawValue: raw, sourceURI: URL(string: "https://example.invalid/source.json"))
    let before = try document.encodeJSON()
    let result = try document.validate()
    #expect(result.isValid)
    #expect(result.evaluationErrors?.isEmpty != false)
    #expect(document.rawValue == raw)
    #expect(try document.encodeJSON() == before)
    #expect(
      try document.value(at: "/components/schemas/Opaque/$ref").value
        == raw.object?["components"]?.object?["schemas"]?.object?["Opaque"]?.object?["$ref"])
  }

  @Test(arguments: [JSONValue.string("not a schema"), JSONValue.array([]), JSONValue.null])
  func schemaObjectsMustStillBeObjectsOrBooleans(schema: JSONValue) throws {
    let document = try OpenAPIJSONDocument(rawValue: [
      "openapi": "3.1.0",
      "info": ["title": "API", "version": "1"],
      "components": ["schemas": ["Invalid": schema]],
    ])
    let result = try document.validate()
    #expect(!result.isValid)
    #expect(result.evaluationErrors?.isEmpty != false)
  }

  @Test
  func completeOfflineMetaSchemaRegistry() throws {
    let registry = try OpenAPIValidator.offlineMetaSchemas()
    #expect(registry.count == 8)
    let root = "https://json-schema.org/draft/2020-12/schema"
    let schema = try JSONSchema.Schema(
      rawSchema: #require(registry[root]),
      context: Context(dialect: .draft2020_12, remoteSchema: registry),
      baseURI: #require(URL(string: root)))
    for (uri, value) in registry {
      #expect(value.object?["$id"]?.string == uri)
      let result = schema.validate(value)
      #expect(result.isValid)
      #expect(result.evaluationErrors?.isEmpty != false)
    }
    let result = schema.validate(try JSONValue.parse(resourceData("openapi-3.1-2025-09-15.schema")))
    #expect(result.isValid)
    #expect(result.evaluationErrors?.isEmpty != false)
    let references = try #require(registry[root]?.object?["allOf"]?.array)
    #expect(references.count == 7)
    for reference in references {
      let relativeURI = try #require(reference.object?["$ref"]?.string)
      let uri = try #require(
        URL(string: relativeURI, relativeTo: URL(string: root))?.absoluteString)
      #expect(registry[uri] != nil)
    }
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENAPI_CORPUS_PATH"] != nil))
  func pinnedOpenAICorpusStructuralValidation() throws {
    let path = try #require(ProcessInfo.processInfo.environment["OPENAPI_CORPUS_PATH"])
    let document = try OpenAPIJSONDocument(data: Data(contentsOf: URL(fileURLWithPath: path)))
    let result = try document.validate()
    for error in allErrors(result.errors ?? []) where error.errors?.isEmpty != false {
      print("Corpus: \(error.keyword) at \(error.instanceLocation): \(error.message)")
    }
    #expect(result.evaluationErrors?.isEmpty != false)
    #expect(result.isValid)
  }

  private func allErrors(_ errors: [ValidationError]) -> [ValidationError] {
    errors.flatMap { [$0] + allErrors($0.errors ?? []) }
  }

  // Reproduce the removed pre-0.14 workaround only in tests to prove the strictness gain.
  private func legacyStrippedSchema() throws -> JSONSchema.Schema {
    func strip(_ value: JSONValue) -> JSONValue {
      switch value {
      case .object(let object):
        var transformed = JSONObject()
        for (key, value) in object
        where key != "unevaluatedProperties" && key != "dependentSchemas" {
          transformed[key] = strip(value)
        }
        return .object(transformed)
      case .array(let values): return .array(values.map(strip))
      default: return value
      }
    }
    return try JSONSchema.Schema(
      rawSchema: strip(JSONValue.parse(resourceData("openapi-3.1-2025-09-15.schema"))),
      context: Context(dialect: .draft2020_12, remoteSchema: OpenAPIValidator.offlineMetaSchemas()),
      baseURI: #require(URL(string: "https://spec.openapis.org/oas/3.1/schema/2025-09-15")))
  }

  private func resourceData(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: "json"))
    return try Data(contentsOf: url)
  }
}
