# Building Your First OpenAPI Document

Create a typed OpenAPI 3.1 document, validate it, and encode stable JSON.

## Define a Schemable model

Start with a Swift model that conforms to `Schemable`. The `swift-json-schema` macros generate the JSON Schema used by the OpenAPI component.

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
```

## Register typed components

Register each model that you plan to reference. `Schema(Pet.self)` uses the sanitized Swift type name as the component key.

```swift
Components {
  Schema(Pet.self)
}
```

If you need a custom key, pass `name:` and use the same name at each reference site.

```swift
Components {
  Schema(Pet.self, name: "PetResource")
}
```

## Reference components from bodies and schemas

Use `JSONBody(Pet.self)` for an `application/json` request or response body. Use `OpenAPISchemaValue.component(Pet.self)` when composing another schema value.

```swift
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
```

Typed references produce `$ref` values such as `#/components/schemas/Pet`; they do not register the component automatically.

## Use dynamic builders

The result builders accept `for` loops and optional `if` blocks, which is useful when your spec is generated from route metadata or feature flags.

```swift
let versions = ["v1", "v2"]
let includeDebugRoute = false

let document = OpenAPIDocument {
  Info(title: "Pet API", version: "1.0.0")

  Components {
    Schema(Pet.self)
  }

  for version in versions {
    Path("/\(version)/pets") {
      GET(operationID: "listPets_\(version)") {
        Response(.ok) {
          JSONBody(schema: .array(.component(Pet.self)))
        }
      }
    }
  }

  if includeDebugRoute {
    Path("/debug/openapi") {
      GET(operationID: "debugOpenAPI") {
        Response(.ok)
      }
    }
  }
}
```

## Validate and write canonical JSON

Call `validate()` when you want to inspect the result, or `OpenAPIValidator.assertValid(_:)` when invalid documents should throw. Then encode canonical JSON for generated files or snapshot tests.

```swift
let result = try document.validate()
precondition(result.isValid)

try OpenAPIValidator.assertValid(document)
let data = try document.encodeCanonicalJSON(prettyPrinted: true)
```

Canonical JSON sorts object keys, preserves array order from the builders, and appends a trailing newline.

## Know the boundary

This target builds OpenAPI documents; it does not inspect server frameworks. For server-to-spec Vapor integration, use the companion Vapor package (`swift-openapi-schema-vapor`) when available.
