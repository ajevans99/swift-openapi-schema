import Foundation
import JSONSchema

/// Offline structural validation against the unmodified official OpenAPI 3.1 meta-schema.
///
/// This schema deliberately does not validate embedded Schema Objects' keyword or custom
/// dialect semantics. Document references are not resolved, and no network loading occurs.
public enum OpenAPIValidator {
  public static func validate(_ document: OpenAPIDocument) throws -> ValidationResult {
    guard document.version == .v3_1_0 else {
      throw OpenAPIError.unsupportedValidationVersion(document.version)
    }
    return try validationSchema().validate(document.jsonValue())
  }

  /// Validates the original parsed value without dereferencing or rewriting any source nodes.
  public static func validate(_ document: OpenAPIJSONDocument) throws -> ValidationResult {
    try validationSchema().validate(document.rawValue)
  }

  private static func validationSchema() throws -> JSONSchema.Schema {
    let rawSchema = try JSONValue.parse(
      resourceData(named: "openapi-3.1-2025-09-15.schema", extension: "json"))
    return try JSONSchema.Schema(
      rawSchema: rawSchema,
      context: Context(
        dialect: .draft2020_12,
        remoteSchema: offlineMetaSchemas()
      ),
      baseURI: URL(string: "https://spec.openapis.org/oas/3.1/schema/2025-09-15")!
    )
  }

  static func offlineMetaSchemas() throws -> [String: JSONValue] {
    let root = "https://json-schema.org/draft/2020-12"
    var schemas = [
      "\(root)/schema": try JSONValue.parse(
        resourceData(named: "json-schema-draft-2020-12.schema", extension: "json"))
    ]
    for vocabulary in [
      "core", "applicator", "unevaluated", "validation", "meta-data", "format-annotation",
      "content",
    ] {
      schemas["\(root)/meta/\(vocabulary)"] = try JSONValue.parse(
        resourceData(
          named: "json-schema-draft-2020-12-meta-\(vocabulary).schema", extension: "json"))
    }
    return schemas
  }

  public static func assertValid(_ document: OpenAPIDocument) throws {
    try assertValidResult(validate(document))
  }

  /// Throws `OpenAPIError.validationFailed` with the validator's nested diagnostic paths.
  public static func assertValid(_ document: OpenAPIJSONDocument) throws {
    try assertValidResult(validate(document))
  }

  private static func assertValidResult(_ result: ValidationResult) throws {
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

extension OpenAPIJSONDocument {
  /// Runs offline OpenAPI structural validation separately from parsing and checked views.
  ///
  /// Embedded Schema Objects and their `$ref` and `$schema` values remain untouched.
  /// Their keyword and dialect semantics are outside this validator's scope.
  public func validate() throws -> ValidationResult {
    try OpenAPIValidator.validate(self)
  }
}
