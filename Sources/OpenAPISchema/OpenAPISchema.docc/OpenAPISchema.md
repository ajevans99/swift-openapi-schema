# ``OpenAPISchema``

Author, import, inspect, and validate OpenAPI documents in Swift.

## Overview

`OpenAPISchema` is the core document-building target for `swift-openapi-schema`. It provides result-builder APIs for OpenAPI documents, paths, operations, request bodies, responses, components, security schemes, and schema references.

``OpenAPIJSONDocument`` imports external OpenAPI 3.1 JSON while preserving unknown fields,
extensions, object order, and exact number tokens. Its checked operation catalog exposes
parameter/server/security inheritance and request/response content with original JSON Pointers
and retrieval URIs. Authored documents expose the same representation through
``OpenAPIDocument/documentRepresentation(sourceURI:)``.

Parsing, checked views, and full document validation are separate operations. External
Reference Objects resolve only from explicitly supplied documents, without network loading.
JSON Schema references and dialects are preserved rather than rewritten.

Document validation uses the untouched official OpenAPI 3.1 structural meta-schema
with a complete offline Draft 2020-12 registry. It does not compile or validate
the semantics of embedded Schema Objects or resolve their references.

The package is designed to work with `swift-json-schema`: define `@Schemable` models, register them as OpenAPI components, reference those components from request and response bodies, validate the finished OpenAPI 3.1 document, then write canonical JSON for stable diffs and snapshots.

```swift
import OpenAPISchema
import JSONSchema
import JSONSchemaBuilder

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
  }
}

try OpenAPIValidator.assertValid(document)
let json = try document.encodeCanonicalJSON()
```

## Topics

### Essentials

- <doc:BuildingYourFirstOpenAPIDocument>

### Documents and validation

- ``OpenAPIDocument``
- ``OpenAPIJSONDocument``
- ``OpenAPILocatedValue``
- ``OpenAPISourceLocation``
- ``OpenAPIImportError``
- ``OpenAPIVersion``
- ``OpenAPIValidator``
- ``OpenAPIError``

### Components and schemas

- ``Components``
- ``Schema``
- ``OpenAPISchemaValue``
- ``BearerAuth(_:bearerFormat:)``
- ``APIKeyAuth(_:in:keyName:)``

### Paths, operations, and bodies

- ``OpenAPIOperationView``
- ``OpenAPIParameterView``
- ``OpenAPIRequestBodyView``
- ``OpenAPIResponseView``
- ``OpenAPIMediaTypeView``
- ``Path``
- ``GET(operationID:content:)``
- ``POST(operationID:content:)``
- ``Request``
- ``Response``
- ``JSONBody(_:)``
- ``JSONBody(_:name:)``
- ``JSONBody(schema:)``
