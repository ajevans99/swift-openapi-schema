# Swift OpenAPI Schema

`swift-openapi-schema` is the core Swift package for authoring, importing, inspecting, and validating OpenAPI documents. It pairs a result-builder API with a lossless JSON document representation and [`swift-json-schema`](https://github.com/ajevans99/swift-json-schema).

Use this package when you want to:

- build OpenAPI 3.1 documents directly in Swift;
- import external OpenAPI 3.1 JSON without discarding unknown fields or schema number tokens;
- inspect source-located operations, inherited parameters, media types, and component schemas;
- register component schemas from raw `JSONValue` or `@Schemable` types;
- reference typed components from request and response bodies;
- generate canonical, snapshot-friendly JSON output;
- validate generated documents against the bundled OpenAPI 3.1 meta-schema.

## Installation

Requires Swift 6.1 or newer and `swift-json-schema` 0.14.0 or newer. Existing platform minimums are unchanged.

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

Builders preserve declaration order for arrays and objects in the emitted OpenAPI document.

## Importing and inspecting OpenAPI JSON

`OpenAPIJSONDocument` retains the entire `OrderedJSON.JSONValue` tree, including unknown OpenAPI fields, extensions, raw JSON Schema objects/booleans, and Reference Objects. Import does not rebuild the document through the authoring DSL.

```swift
import Foundation
import OpenAPISchema

let imported = try OpenAPIJSONDocument(
  data: Data(contentsOf: URL(fileURLWithPath: "openapi.json")),
  sourceURI: URL(string: "https://example.com/spec/openapi.json")
)
let raw = imported.rawValue
let exported = try imported.encodeJSON(prettyPrinted: true)
let componentSchemas = try imported.componentSchemas()

for operation in try imported.operations() {
  print(operation.method, operation.path, operation.operationID ?? "(unnamed)")
  for response in operation.responses {
    for media in response.content {
      if let schema = media.schema {
        print(response.status, media.mediaType, schema.location)
      }
    }
  }
}
```

An authored OpenAPI 3.1 document exposes the same representation:

```swift
let shared = try document.documentRepresentation()
let operations = try shared.operations()
```

Import checks the JSON object envelope and `openapi: "3.1.x"` version only. It does not require full meta-schema validity. Malformed JSON throws `JSONParseError` with byte offset, line, and column; checked document/view failures throw `OpenAPIImportError` with retrieval URI and JSON Pointer. This allows compatibility issues to be inspected without silently modifying an input.

`encodeJSON` preserves object declaration order, array order, and exact number tokens, including numbers outside Swift numeric ranges. It does not promise byte-for-byte whitespace or string-escape preservation. Duplicate JSON object keys follow OrderedJSON's last-write-wins semantics; duplicate member occurrences cannot be recovered.

### Checked operation views

`operations()` enumerates `paths` operations in declaration order and checks consumed shapes, duplicate operation IDs, and parameter identities. It fails at the first malformed shape or unsupported reference. Raw fields remain accessible through `source.value` and `rawValue` even when no typed helper exists.

- Parameters inherit from the Path Item. Operation parameters override by the exact `(name, in)` identity; distinct locations with the same name remain distinct. Duplicates within a single scope are errors.
- Operation security replaces document security. An absent field inherits; explicit `[]` removes requirements; `[{}]` retains an anonymous-access alternative.
- Server declarations use operation, then Path Item, then document scope. Empty declarations are retained; helpers do not synthesize a `/` server. Raw scopes distinguish missing and empty declarations.
- Request bodies, response statuses (`200`, `2XX`, `default`), and all content media types retain their original values. A media type's missing `schema` is `nil`, not an invented empty schema.
- `componentSchemas()` returns only actual `components.schemas` entries. Arbitrary metadata containing `$ref` is not mistaken for JSON Schema.

### References and source locations

Every located value has `value` and `location` (`sourceURI: URL?`, `pointer: String`). `value(at:)` accepts a plain RFC 6901 pointer; `member(_:)` accesses a checked object member. Pointer escaping supports `/`, `~`, empty keys, and array indices.

Reference Objects are resolved only in OpenAPI object positions such as parameters, request bodies, and responses. JSON Schema `$ref`, `$id`, anchors, and dialect semantics are **not** rewritten or resolved by this importer. The original complete document and source locations remain available to a schema consumer.

```swift
let imported = try OpenAPIJSONDocument(
  data: rootData,
  sourceURI: URL(string: "https://example.com/spec/openapi.json"),
  externalDocuments: [
    URL(string: "https://example.com/spec/shared.json")!: sharedJSONValue
  ]
)
```

Retrieval URIs must be absolute and fragment-free. No network or filesystem reference loading is performed: callers explicitly supply external JSON values. Local and relative/absolute supplied-document references support percent-encoded JSON Pointer fragments. Missing documents/targets, anchor fragments, reference cycles, and Path Item `$ref` with non-extension siblings produce located errors rather than guessed results.

Reference-bearing views expose both `source` (the original Reference Object) and `target` (the resolved object). Reference Object `summary`/`description` overrides are retained in `source`, not merged into or written over `target`. Schemas under an external target keep that target's retrieval URI and pointer; relative schema references must be evaluated in that original scope.

### Pinned acceptance corpus

The optional acceptance test uses `openai/openai-openapi` revision `4bb21ba8e9213c3d955b69dc3f76dd7537439828`, retaining its MIT license alongside the downloaded fixture. Run:

```sh
bash Scripts/test-openai-corpus.sh /absolute/path/to/corpus-artifacts
```

The script verifies SHA-256 checksums before testing. The JSON checksum is `3d6223349eadfd937624b9e6b8abf596ec2f680a1a367889cf6a6f924e568127`; the license checksum is `bcba3de214851cce46ed5af42d6698044616eeace887c3231bc7a20474ab639e`. Import/export equality and the checked catalog cover 215 paths, 338 operations, and 1,852 component schemas.

That same unmodified corpus also passes the bundled official OpenAPI **structural** meta-schema under `swift-json-schema` 0.14.0, without validation or evaluation errors. This does not establish semantic validity of embedded JSON Schemas, reference correctness, every normative OpenAPI rule, or representability as generated Swift models.

## Validation

`OpenAPIDocument.jsonValue()` performs package-level checks before producing JSON, including missing `Info`, duplicate operation IDs, duplicate components, duplicate methods for the same path, and undocumented path parameters.

For OpenAPI 3.1 structural meta-schema validation, use either API with an authored or imported document:

```swift
let result = try document.validate()
if !result.isValid {
  print(result.errors ?? [])
}

try OpenAPIValidator.assertValid(document)
```

`assertValid` throws `OpenAPIError.validationFailed` with flattened validation messages. OpenAPI 3.0.3 can be represented with `OpenAPIVersion.v3_0_3`, but bundled meta-schema validation is currently available only for OpenAPI 3.1.

Validation uses the untouched official OpenAPI 3.1 `2025-09-15` schema and a complete, explicit offline Draft 2020-12 meta-schema registry. No keywords are removed and no reference fetching occurs. Regressions cover strict `unevaluatedProperties` rejection, mutually exclusive license fields, and parameter-style restrictions through `dependentSchemas`, alongside valid authored and official imported examples.

The official structural schema treats embedded Schema Objects as opaque objects/booleans. Compiling those schemas, checking their dialects or references, and validating API payloads are separate responsibilities. Resource origins, licenses, and checksums are recorded in `Sources/OpenAPISchema/Resources/MetaSchemas/README.md`.

## Canonical JSON output

Use canonical encoding for generated files, snapshot tests, and stable diffs:

```swift
let pretty = try document.encodeCanonicalJSON()
let compact = try document.encodeCanonicalJSON(prettyPrinted: false)
```

The existing `encodeCanonicalJSON` API preserves object and array declaration order and always appends a trailing newline. It produces deterministic builder output, not RFC 8785 number/key normalization. Imported `encodeJSON` similarly preserves declaration order and number tokens, without appending a newline.

## Known limitations

- OpenAPI 3.1 validation is bundled; OpenAPI 3.0.3 validation is not bundled yet.
- Typed references must be registered explicitly with `Schema(Model.self)` before use.
- Advanced OpenAPI or JSON Schema features may require `Schema("Name", raw:)`, `.raw(_:)`, or `.rawObject(_:)` until a dedicated helper exists.
- JSON ingestion supports OpenAPI 3.1 JSON, not YAML or OpenAPI 3.0 conversion. The checked catalog covers `paths`, not callback/webhook traversal; these fields remain losslessly available in the raw tree.
- Importing schemas is not compiling or validating their dialects, resolving their references, or generating Swift code.
- This core package builds OpenAPI documents; it does not inspect server routes. For server-to-spec Vapor integration, use the companion Vapor package (`swift-openapi-schema-vapor`) when available and see `docs/vapor-integration-plan.md` for the integration direction.

## Documentation

DocC documentation is included in `Sources/OpenAPISchema/OpenAPISchema.docc/` with a package landing page and a tutorial-style guide.
