import Foundation
import JSONSchema

public enum OpenAPIValidator {
  public static func validate(_ document: OpenAPIDocument) throws -> ValidationResult {
    guard document.version == .v3_1_0 else {
      throw OpenAPIError.unsupportedValidationVersion(document.version)
    }
    let schemaData = try resourceData(named: "openapi-3.1-2025-09-15.schema", extension: "json")
    let schemaString = String(decoding: schemaData, as: UTF8.self)
    let jsonSchemaData = try resourceData(
      named: "json-schema-draft-2020-12.schema", extension: "json")
    let jsonSchemaValue = try JSONDecoder().decode(JSONValue.self, from: jsonSchemaData)
    let rawSchemaValue = try JSONDecoder().decode(JSONValue.self, from: schemaData)
    let validationSchemaValue = removingUnsupportedKeywords(from: rawSchemaValue)
    // swift-json-schema currently false-fails OAS's annotation-heavy
    // unevaluated/dependent annotation checks through refs/conditionals. Keep the
    // official schema bundled and validate against a compatibility copy until that lands.
    let schema = try JSONSchema.Schema(
      rawSchema: validationSchemaValue,
      context: Context(
        dialect: .draft2020_12,
        remoteSchema: [
          "https://json-schema.org/draft/2020-12/schema": jsonSchemaValue
        ]
      ),
      baseURI: URL(string: "https://spec.openapis.org/oas/3.1/schema/2025-09-15")!
    )
    _ = try JSONSchema.Schema(
      instance: schemaString,
      remoteSchemas: [
        "https://json-schema.org/draft/2020-12/schema": jsonSchemaValue
      ]
    )
    return try schema.validate(document.jsonValue())
  }

  public static func assertValid(_ document: OpenAPIDocument) throws {
    let result = try validate(document)
    guard result.isValid else {
      throw OpenAPIError.validationFailed(
        result.errors?.map(flatten) ?? ["Unknown validation error"]
      )
    }
  }

  private static func flatten(_ error: ValidationError) -> String {
    let message =
      "\(error.keyword) at \(error.instanceLocation) (schema \(error.keywordLocation)): \(error.message)"
    guard let errors = error.errors, !errors.isEmpty else {
      return message
    }
    return ([message] + errors.map(flatten)).joined(separator: " -> ")
  }

  private static func removingUnsupportedKeywords(from value: JSONValue) -> JSONValue {
    switch value {
    case .object(let object):
      var transformed: [String: JSONValue] = [:]
      for (key, value) in object
      where key != "unevaluatedProperties" && key != "dependentSchemas" {
        transformed[key] = removingUnsupportedKeywords(from: value)
      }
      return .object(transformed)
    case .array(let values):
      return .array(values.map(removingUnsupportedKeywords))
    default:
      return value
    }
  }

  private static func resourceData(named name: String, extension ext: String) throws -> Data {
    if let url = Bundle.module.url(forResource: name, withExtension: ext) {
      return try Data(contentsOf: url)
    }
    guard
      let url = Bundle.module.url(
        forResource: name,
        withExtension: ext,
        subdirectory: "MetaSchemas"
      )
    else {
      throw OpenAPIError.missingResource("\(name).\(ext)")
    }
    return try Data(contentsOf: url)
  }
}
