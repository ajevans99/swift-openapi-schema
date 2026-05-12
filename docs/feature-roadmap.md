# Feature Roadmap

This document plans the next four feature areas for `swift-openapi-schema`.
Each plan is scoped to preserve the package's current goals: deterministic
OpenAPI output, typed schema reuse from `swift-json-schema`, and a small builder
surface that remains easy to validate.

## 1. Unresolved `$ref` validation

### Goal

Detect component references that point to missing schemas before users publish
or generate clients from an invalid OpenAPI document.

### Proposed API

```swift
try document.validateReferences()
try OpenAPIValidator.assertValid(document, checks: [.schema, .references])
```

`OpenAPIValidator.assertValid(_:)` should keep its current schema-validation
behavior by default. Reference validation can be added as a new explicit check,
then considered for the default once it is mature.

### Implementation plan

1. Add an internal walker over `JSONValue` that collects all local `$ref`
   strings matching `#/components/schemas/{name}`.
2. Add an internal helper that extracts declared component schema names from the
   document JSON.
3. Report every missing component in a new error case, for example
   `OpenAPIError.unresolvedReference(String)`, or a batch error such as
   `OpenAPIError.unresolvedReferences([String])`.
4. Keep validation local-only at first. External and non-schema references
   should be ignored until the package has first-class support for them.
5. Add Swift Testing coverage for valid typed references, missing manual
   references, missing typed `JSONBody(Pet.self)` registration, and nested array
   references.

### Open questions

- Should unresolved references be checked by `OpenAPIDocument.jsonValue()` or
  only by validator APIs?
- Should this feature eventually validate parameters, responses, examples, and
  request body component references too?

## 2. Automatic Schemable component registration

### Goal

Make `JSONBody(Pet.self)` safe by avoiding dangling component references when a
matching `Schema(Pet.self)` was not manually added to `Components`.

### Proposed API

```swift
let document = OpenAPIDocument {
  Path("/pets") {
    POST(operationID: "createPet") {
      Request {
        JSONBody(Pet.self, registration: .automatic)
      }
      Response(.created) {
        JSONBody(Pet.self, registration: .automatic)
      }
    }
  }
}
```

The default should stay explicit for now:

```swift
Components {
  Schema(Pet.self)
}
JSONBody(Pet.self)
```

That preserves predictable document structure while an automatic registry is
designed and tested.

### Implementation plan

1. Introduce an internal `SchemableComponentReference` type that carries the
   component name and a schema provider closure.
2. Extend `Body` or `OpenAPISchemaValue` so typed references can optionally
   expose the schema they reference.
3. During document JSON generation, collect typed references from operations and
   merge missing schemas into components when automatic registration is enabled.
4. Detect conflicts where an existing component uses the same name but produces a
   different schema. Surface this as a deterministic error instead of silently
   overriding.
5. Add tests for automatic registration, explicit override names, duplicate
   conflicts, and repeated references to the same Schemable type.

### Open questions

- Should registration be document-wide configuration instead of a per-body
  option?
- Should automatic registration apply only to request/response bodies, or also
  to future parameter and example helpers?

## 3. Examples support

### Goal

Add ergonomic OpenAPI examples for parameters, request bodies, responses, and
component schemas while preserving deterministic JSON output.

### Proposed API

```swift
Components {
  Schema(Pet.self) {
    Example("cat", value: Pet(id: "1", name: "Milo", tag: "cat"))
  }
}

Response(.ok) {
  JSONBody(Pet.self) {
    Example(value: Pet(id: "1", name: "Milo", tag: "cat"))
  }
}
```

Typed examples should require `Encodable` so values can be converted to
`JSONValue`. Raw `JSONValue` examples should remain available for callers that
do not want typed examples.

### Implementation plan

1. Add `Example` and `Examples` builder components that can encode either a raw
   `JSONValue` or an `Encodable` value.
2. Add body-level support for OpenAPI `example` and `examples` fields under a
   media type object.
3. Add response and parameter example support after body examples are stable.
4. Decide how schema-level examples are represented. OpenAPI 3.1 allows JSON
   Schema keywords, but generator compatibility should be tested.
5. Add snapshots that prove examples are sorted by name and preserve arrays in
   declaration order.

### Open questions

- Should typed examples validate against the associated Schemable schema during
  document generation?
- Should example values support external references and summaries/descriptions
  from day one?

## 4. Broader OpenAPI 3.1 coverage

### Goal

Expand the builder surface beyond the current core document, paths, operations,
parameters, bodies, responses, components, and security schemes.

### Proposed feature slices

1. `webhooks` builder support for event-driven APIs.
2. `callbacks` support on operations.
3. `multipart/form-data` and `application/x-www-form-urlencoded` request body
   builders.
4. Discriminator and composition helpers for `oneOf`, `anyOf`, and typed
   Schemable enum models.

### Implementation plan

1. Add `Webhook` and `Webhooks` document components that reuse the existing
   `Path` and `Operation` machinery where possible.
2. Add `Callback` as an operation component with expression-keyed path items.
3. Add form body builders that make required fields, binary fields, arrays, and
   per-part encodings explicit.
4. Add composition helpers to `OpenAPISchemaValue` before trying to infer
   discriminator behavior from Schemable enums.
5. Validate each slice against the bundled OpenAPI 3.1 meta-schema and add
   SnapshotTesting references for canonical output.

### Open questions

- Which downstream generator should define compatibility expectations:
  `swift-openapi-generator`, OpenAPI Generator, or both?
- Should each slice ship independently, or should the package wait for a larger
  OpenAPI 3.1 completeness milestone?
