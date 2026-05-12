# Swift OpenAPI Schema

`swift-openapi-schema` is the core Swift package for building deterministic OpenAPI documents in code. It pairs a result-builder API for OpenAPI structure with [`swift-json-schema`](https://github.com/ajevans99/swift-json-schema) so your Swift `@Schemable` models can be the source of truth for component schemas.

Use this package when you want to:

- build OpenAPI 3.1 documents directly in Swift;
- register component schemas from raw `JSONValue` or `@Schemable` types;
- reference typed components from request and response bodies;
- generate canonical, snapshot-friendly JSON output;
- validate generated documents against the bundled OpenAPI 3.1 meta-schema.

## Installation

Add the package to your `Package.swift` dependencies:

```swift
.package(url: "https://github.com/ajevans99/swift-openapi-schema.git", branch: "main")
```

Then add `OpenAPISchema` to the target that builds your specification.

## Quick start

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
  Info(title: "Pet API", version: "1.0.0")
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

try OpenAPIValidator.assertValid(document)
let data = try document.encodeCanonicalJSON()
```

## Typed `@Schemable` APIs

The core typed workflow is:

1. Define a `@Schemable` Swift model.
2. Register the model in `Components`.
3. Reference that component anywhere a schema is needed.

```swift
@Schemable
struct Pet {
  let id: String
  let name: String
}

let document = OpenAPIDocument {
  Info(title: "Pet API", version: "1.0.0")

  Components {
    Schema(Pet.self)
  }

  Path("/pets") {
    GET(operationID: "listPets") {
      Response(.ok) {
        JSONBody(schema: .array(.component(Pet.self)))
      }
    }

    POST(operationID: "createPet") {
      Request {
        JSONBody(Pet.self)
      }
      Response(.created) {
        JSONBody(Pet.self)
      }
    }
  }
}
```

`Schema(Pet.self)` registers the generated JSON Schema under the default component name `Pet`. `JSONBody(Pet.self)` emits an `application/json` body whose schema is a `$ref` to `#/components/schemas/Pet`. `OpenAPISchemaValue.component(Pet.self)` produces the same typed `$ref` when composing arrays, objects, parameters, or raw body schemas.

Pass `name:` when the OpenAPI component key should differ from the Swift type name:

```swift
Components {
  Schema(Pet.self, name: "PetResource")
}

Response(.ok) {
  JSONBody(Pet.self, name: "PetResource")
}
```

Typed references do not automatically register components. Add each referenced model to `Components` with `Schema(Model.self)`.

## Dynamic result-builder usage

The document builders support dynamic Swift control flow such as `for` loops and optional `if` blocks. Use this to generate repeated paths, media types, responses, or components from your own metadata.

```swift
let versions = ["v1", "v2"]
let includeAdmin = false
let mediaTypes: [MediaType] = [.json, .textPlain]

let document = OpenAPIDocument {
  Info(title: "Dynamic API", version: "1.0.0")

  Components {
    Schema(Pet.self)
    if includeAdmin {
      BearerAuth("adminBearer")
    }
  }

  for version in versions {
    Path("/\(version)/pets") {
      GET(operationID: "listPets_\(version)") {
        Response(.ok) {
          for mediaType in mediaTypes {
            Body(mediaType, schema: .array(.component(Pet.self)))
          }
        }
      }
    }
  }
}
```

Builders preserve declaration order for arrays in the emitted OpenAPI document. Object keys are sorted when encoded canonically.

## Validation

`OpenAPIDocument.jsonValue()` performs package-level checks before producing JSON, including missing `Info`, duplicate operation IDs, duplicate components, duplicate methods for the same path, and undocumented path parameters.

For OpenAPI 3.1 meta-schema validation, use either API:

```swift
let result = try document.validate()
if !result.isValid {
  print(result.errors ?? [])
}

try OpenAPIValidator.assertValid(document)
```

`assertValid` throws `OpenAPIError.validationFailed` with flattened validation messages. OpenAPI 3.0.3 can be represented with `OpenAPIVersion.v3_0_3`, but bundled meta-schema validation is currently available only for OpenAPI 3.1.

## Canonical JSON output

Use canonical encoding for generated files, snapshot tests, and stable diffs:

```swift
let pretty = try document.encodeCanonicalJSON()
let compact = try document.encodeCanonicalJSON(prettyPrinted: false)
```

Canonical output uses sorted object keys, preserves array order from your builder declarations, and always appends a trailing newline.

## Known limitations

- OpenAPI 3.1 validation is bundled; OpenAPI 3.0.3 validation is not bundled yet.
- Typed references must be registered explicitly with `Schema(Model.self)` before use.
- Advanced OpenAPI or JSON Schema features may require `Schema("Name", raw:)`, `.raw(_:)`, or `.rawObject(_:)` until a dedicated helper exists.
- The bundled validator uses the official OpenAPI 3.1 schema plus a compatibility copy that omits `unevaluatedProperties` and `dependentSchemas` while `swift-json-schema` support matures.
- This core package builds OpenAPI documents; it does not inspect server routes. For server-to-spec Vapor integration, use the companion Vapor package (`swift-openapi-schema-vapor`) when available and see `docs/vapor-integration-plan.md` for the integration direction.

## Documentation

DocC documentation is included in `Sources/OpenAPISchema/OpenAPISchema.docc/` with a package landing page and a tutorial-style guide.
