# Swift OpenAPI Schema

`swift-openapi-schema` is a Swift OpenAPI document builder designed to use
[`swift-json-schema`](https://github.com/ajevans99/swift-json-schema) as the
schema source of truth.

The initial package focuses on:

- deterministic, canonical JSON output;
- builder-style OpenAPI document construction;
- component schemas backed by raw `JSONValue` or `@Schemable` types;
- bundled OpenAPI 3.1 meta-schema validation;
- snapshot-friendly output for generated API documents.

Vapor integration is intentionally out of scope for the first package surface and
will be added separately.

## Example

```swift
import OpenAPISchema
import JSONSchema
import JSONSchemaBuilder

@Schemable
struct Pet {
  let id: String
  let name: String
  let tag: String?
}

let document = OpenAPIDocument(.v3_1_0) {
  Info(title: "Example API", version: "1.0.0")
  Server("https://api.example.com")

  Components {
    BearerAuth("bearerAuth")
    Schema(Pet.self)
  }

  Path("/pets/{petId}") {
    GET(operationID: "getPetByID") {
      Tags("Pets")
      Summary("Get a pet")
      Security("bearerAuth")
      PathParameter("petId", schema: .string(format: "uuid"))

      Response(.ok) {
        JSONBody(Pet.self)
      }

      Response(.notFound) {
        JSONBody(schema: .object(
          properties: ["message": .string()],
          required: ["message"]
        ))
      }
    }
  }
}

let data = try document.encodeCanonicalJSON()
try OpenAPIValidator.assertValid(document)
```

`Schema(Pet.self)` registers the Schemable type under the default component
name `Pet`, and `JSONBody(Pet.self)` emits a JSON body whose schema references
`#/components/schemas/Pet`. Pass `name:` to either helper when you want a custom
component key.

## Canonical output

Canonical output is object-key-sorted JSON with arrays preserved in declaration
order, a trailing newline, and optional pretty printing.

```swift
let data = try document.encodeCanonicalJSON(prettyPrinted: true)
```

## Validation

The package vendors the official OpenAPI 3.1 schema from:

`https://spec.openapis.org/oas/3.1/schema/2025-09-15`

OpenAPI 3.0.3 is represented in the version enum but validation is not bundled
yet. The next compatibility milestone is testing the emitted schema surface
against Apple `swift-openapi-generator`.

The bundled validator parses the official schema as-is, then validates with a
compatibility copy that omits `unevaluatedProperties` and `dependentSchemas`.
Those keywords currently produce false negatives in `swift-json-schema` for the
OpenAPI schema's ref-heavy conditional structure; the vendored source remains
unchanged so full validation can be enabled once that support is complete.
