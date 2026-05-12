# Vapor Integration Plan

This plan sketches a companion Vapor integration for `swift-openapi-schema`.
The goal is server-to-spec generation: developers write type-safe Vapor routes
and get an OpenAPI 3.1 document backed by `@Schemable` Swift types.

The integration should start with Vapor 4 because it is stable, but its shape
should be compatible with Vapor 5's macro-routing direction.

## Vapor 5 research notes

I reviewed the `vapor-5` branch from `vapor/vapor` in a separate worktree so the
local dirty `~/Documents/vapor` checkout was not disturbed.

Relevant findings:

1. Vapor 5 currently uses Swift tools 6.2 and has a default `MacroRouting` trait.
2. The package exposes `VaporMacros` with `@Controller`, attached route macros
   such as `@GET`/`@POST`, freestanding route macros such as `#GET`, and
   `@AuthMiddleware`.
3. `@Controller` expands a `RouteCollection` conformance by walking member
   functions and reading route attributes from syntax.
4. Route macros generate wrapper functions that adapt typed handler output to
   `Response`.
5. `Route` already stores `method`, `path`, `requestType`, `responseType`, and
   `userInfo`, but the macro-generated wrappers currently register `Request.self`
   and `Response.self`, so OpenAPI metadata should not depend on those fields
   alone.
6. Vapor 5's macro path parameters are currently type-derived names like
   `:int0`; OpenAPI should prefer explicit semantic names such as `{petID}`.

The local `~/Documents/vapor` checkout also has an `openapi` branch with a
prototype that adds an OpenAPI trait, a `VaporOpenAPI` target, route metadata,
an application registry, and marker macros such as `@RequestBody` and
`@Response`. That prototype validates the broad direction, but it duplicates
OpenAPI model types that this package now owns. The integration here should use
the public Vapor packages and this package's `OpenAPISchema` model instead of
vendoring or depending on that local branch.

## Package strategy

Create a separate companion package, tentatively named
`swift-openapi-schema-vapor`, rather than adding Vapor targets to this package.

Reasons:

1. Vapor should remain an optional dependency for `swift-openapi-schema` users.
2. Vapor 5 currently requires Swift tools 6.2, while this package uses Swift
   tools 6.0.
3. Vapor 4 and Vapor 5 support should be released on independent timelines.
4. Macro targets can change quickly without forcing SemVer breaks in the core
   OpenAPI builder.

Proposed products:

```swift
.library(name: "OpenAPISchemaVapor", targets: ["OpenAPISchemaVapor"])
.library(name: "OpenAPISchemaVaporMacros", targets: ["OpenAPISchemaVaporMacros"])
```

Proposed targets:

1. `OpenAPISchemaVaporCore`: Vapor-version-light metadata and document building.
2. `OpenAPISchemaVapor`: Vapor 4 manual registration and serving helpers.
3. `OpenAPISchemaVaporMacros`: Vapor 5 macro-facing APIs.
4. `OpenAPISchemaVaporMacroPlugin`: SwiftSyntax implementation for Vapor 5 POC.

The runtime metadata target should avoid exposing Vapor 5 macro types in public
API. Keep macro churn isolated to the macro targets.

## Baseline without integration

Today, users can manually build an `OpenAPIDocument` and serve it from Vapor:

```swift
let document = OpenAPIDocument {
  Info(title: "Pets API", version: "1.0.0")
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

app.get("openapi.json") { _ in
  String(decoding: try document.encodeCanonicalJSON(), as: UTF8.self)
}
```

The integration should improve ergonomics and correctness: route metadata is
collected from the Vapor app, `Schemable` conformance is compiler-enforced, and
the generated document can be validated and snapshotted.

## Runtime metadata model

Define a small metadata layer that can be emitted manually or by macros:

```swift
public struct OpenAPIRouteMetadata: Sendable {
  public var method: HTTPMethod
  public var path: [OpenAPIPathSegment]
  public var operationID: String
  public var tags: [String]
  public var summary: String?
  public var description: String?
  public var parameters: [OpenAPIParameterMetadata]
  public var requestBody: OpenAPIRequestBodyMetadata?
  public var responses: [OpenAPIResponseMetadata]
  public var security: [OpenAPISecurityMetadata]
}
```

Typed metadata constructors should enforce schemas at compile time:

```swift
public static func jsonRequestBody<T>(
  _ type: T.Type,
  required: Bool = true
) -> OpenAPIRequestBodyMetadata where T: Content, T: Schemable

public static func jsonResponse<T>(
  _ status: HTTPStatus,
  _ type: T.Type
) -> OpenAPIResponseMetadata where T: ResponseEncodable, T: Schemable
```

Macro-generated code must call generic helpers like these rather than storing
only `Any.Type` or strings. That is how missing `Schemable` conformance becomes
a compiler error.

## Vapor 4 manual integration

Vapor 4 does not have first-class macro routing, so the stable integration
should start as explicit route metadata registration.

Proposed API:

```swift
app.post("pets") { req async throws -> Pet in
  let body = try req.content.decode(CreatePet.self)
  return try await createPet(body)
}
.documented(
  operationID: "createPet",
  requestBody: .json(CreatePet.self),
  responses: [
    .json(.created, Pet.self),
    .json(.badRequest, ErrorResponse.self),
  ]
)
```

Application helpers:

```swift
app.openAPI.info = Info(title: "Pets API", version: "1.0.0")
try app.openAPI.register(collection: PetRoutes())
let document = try app.openAPI.document()
try app.openAPI.serveJSON(at: "openapi.json")
```

Implementation steps:

1. Add an `Application.OpenAPI` storage key containing info, servers, components,
   security schemes, and route metadata.
2. Add `Route.documented(...)` helpers that append metadata to the application
   registry after route registration.
3. Convert Vapor path components to OpenAPI templates, preserving explicit
   names for `:petID` path components.
4. Convert typed request and response metadata into `OpenAPISchema` components
   via `Schema(T.self)` and references via `JSONBody(T.self)`.
5. Add `app.openAPI.document()` that builds and validates an `OpenAPIDocument`.
6. Add `app.openAPI.serveJSON(...)` for a canonical JSON endpoint.

Vapor 4 constraints:

1. Manual request decoding inside handlers cannot be discovered automatically.
2. Return types of closures are not reliably introspectable from runtime route
   metadata.
3. Query and header parameters should be explicit metadata at first.

## Vapor 5 macro POC

The Vapor 5 POC should prove that macros can reduce the manual metadata to a
small set of type-safe annotations.

Desired user code:

```swift
@Schemable
struct CreatePet: Content {
  let name: String
  let tag: String?
}

@Schemable
struct Pet: Content {
  let id: UUID
  let name: String
  let tag: String?
}

@Controller
struct PetController {
  @POST("pets")
  @RequestBody(CreatePet.self)
  @Response(.created, Pet.self)
  func create(req: Request, body: CreatePet) async throws -> Pet {
    try await createPet(body)
  }
}
```

Generated code should effectively do two things:

1. Register the Vapor route normally.
2. Register OpenAPI metadata through generic helpers that require
   `Content & Schemable` for request bodies and `ResponseEncodable & Schemable`
   for responses.

Important macro design rule: do not rely on peer macros communicating with each
other. Swift macro expansion ordering makes that fragile. Instead, use an
aggregate macro such as `@Controller` or a dedicated `@OpenAPIController` to
walk each member function's source syntax and read marker attributes including
`@GET`, `@POST`, `@RequestBody`, `@Response`, `@Path`, `@Query`, and `@Header`.

Potential macro APIs:

```swift
@OpenAPIController
struct PetController {
  @POST("pets", "{petID}")
  @Path("petID", UUID.self)
  @Response(.ok, Pet.self)
  func get(req: Request, petID: UUID) async throws -> Pet
}
```

or, with stricter convention:

```swift
@OpenAPIController
struct PetController {
  @GET("pets", "{petID}")
  @Response(.ok, Pet.self)
  func get(req: Request, petID: UUID) async throws -> Pet
}
```

The POC should start with explicit `@Path`, `@Query`, and `@Header` marker
attributes. Later, it can infer path parameters by matching `{name}` segments to
function parameter labels and emitting diagnostics for mismatches.

## Path, query, and header parameters

OpenAPI needs parameter name, location, requiredness, and schema. Vapor route
syntax alone does not always provide all of that.

Initial API:

```swift
@Path("petID", UUID.self)
@Query("includeDeleted", Bool.self, required: false)
@Header("X-Request-ID", UUID.self, required: false)
```

Rules:

1. Every `{name}` in a macro route path must have a matching `@Path(name, ...)`
   or a matching function parameter label when inference is enabled.
2. Every `@Path` parameter is required.
3. Query and header parameters are explicit in phase one.
4. Supported scalar types should map to `OpenAPISchemaValue` directly; complex
   query/header models can wait.

## Document generation

`app.openAPI.document()` should:

1. Build `Info`, `Server`, `Components`, `Path`, `Operation`, `Parameter`,
   `Request`, and `Response` using this package's existing builder APIs.
2. Register every `Schemable` request and response model in `Components`.
3. Use `JSONBody(T.self)` for typed JSON bodies.
4. Preserve deterministic ordering for paths, operations, components, and
   responses.
5. Run unresolved reference checks and bundled OpenAPI 3.1 meta-schema
   validation before returning or serving the document.

## Proof-of-concept milestones

1. **Vapor 5 macro research spike**
   - Create a throwaway fixture package that depends on Vapor's `vapor-5` branch
     and this package.
   - Confirm an aggregate controller macro can read route and marker attributes
     from handler syntax.
   - Confirm generated generic helper calls fail compilation when a request or
     response type is not `Schemable`.

2. **Core metadata package**
   - Implement version-neutral metadata structs.
   - Implement metadata-to-`OpenAPIDocument` conversion.
   - Add tests that build a document without Vapor.

3. **Vapor 4 manual API**
   - Add `Route.documented(...)`, `Application.openAPI`, and serving helpers.
   - Add a fixture Vapor 4 app with request body, response, path, query, and
     error response metadata.
   - Snapshot the generated `openapi.json`.

4. **Vapor 5 macro POC**
   - Add `@OpenAPIController`, `@RequestBody`, `@Response`, `@Path`, `@Query`,
     and `@Header` macros in a Swift tools 6.2 package.
   - Generate route metadata registration alongside Vapor route registration.
   - Keep Vapor 5 macro APIs experimental until Vapor 5 stabilizes.

5. **Validation and compatibility**
   - Validate generated documents against the OpenAPI 3.1 meta-schema.
   - Snapshot canonical JSON output.
   - Compare a generated fixture document against `swift-openapi-generator` and
     `swift-openapi-vapor` expectations.

## Differentiation from Swift OpenAPI Generator

`swift-openapi-generator` and `swift-openapi-vapor` primarily solve
spec-to-server: start with an OpenAPI document and generate Swift server types.

This integration solves server-to-spec: start with a Vapor application and
generate a canonical OpenAPI document from typed route metadata. The tools can
complement each other, but the integration should be clear that it is for
documenting and validating code-first Vapor services.

## Risks and open questions

1. Vapor 5 macro APIs are alpha and require Swift tools 6.2.
2. Attached peer route macros should not be the source of truth for OpenAPI
   metadata; use aggregate syntax-walking macros or explicit manual metadata.
3. Macro-generated OpenAPI metadata must call generic helper APIs to preserve
   compile-time `Schemable` enforcement.
4. Response-only types should not be forced to conform to `Content`; use
   `ResponseEncodable & Schemable` for response metadata.
5. Streaming responses, files, views, WebSockets, and server-sent events need
   explicit manual metadata and should be out of scope for the first release.
6. The Vapor 4 and Vapor 5 integrations may need separate major-version support
   windows or separate products.
