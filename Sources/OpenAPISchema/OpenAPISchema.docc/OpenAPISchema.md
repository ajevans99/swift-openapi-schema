# ``OpenAPISchema``

Build deterministic OpenAPI documents in Swift.

## Overview

`OpenAPISchema` is the core document-building target for `swift-openapi-schema`. It provides result-builder APIs for OpenAPI documents, paths, operations, request bodies, responses, components, security schemes, and schema references.

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

- ``Path``
- ``GET(operationID:content:)``
- ``POST(operationID:content:)``
- ``Request``
- ``Response``
- ``JSONBody(_:)``
- ``JSONBody(_:name:)``
- ``JSONBody(schema:)``
