import Foundation
import JSONSchema
import JSONSchemaBuilder
import OpenAPISchema
import SnapshotTesting
import Testing

@Schemable
struct Pet {
  let id: String
  let name: String
  let tag: String?

  init(id: String, name: String, tag: String? = nil) {
    self.id = id
    self.name = name
    self.tag = tag
  }
}

struct OpenAPISchemaTests {
  private static let shouldRecord: SnapshotTestingConfiguration.Record = false

  @Test(.snapshots(record: shouldRecord))
  func minimalDocumentSnapshotAndValidation() throws {
    let document = OpenAPIDocument(.v3_1_0) {
      Info(title: "Minimal API", version: "1.0.0")
      Server("https://api.example.com", description: "Production")
    }

    assertSnapshot(of: try document.jsonValue(), as: .json)
    try OpenAPIValidator.assertValid(document)
  }

  @Test(.snapshots(record: shouldRecord))
  func petAPIWithComponentsSecurityAndPathParameter() throws {
    let document = OpenAPIDocument(.v3_1_0) {
      Info(title: "Pet API", version: "1.0.0")
      Server("https://api.example.com")

      Components {
        BearerAuth("bearerAuth")
        Schema("Pet", raw: petSchema)
        Schema("ErrorResponse", raw: errorSchema)
      }

      Path("/pets/{petId}") {
        GET(operationID: "getPetByID") {
          Tags("Pets")
          Summary("Get a pet")
          Description("Returns a single pet by ID.")
          Security("bearerAuth")
          PathParameter("petId", schema: .string(format: "uuid"))

          Response(.ok) {
            JSONBody("Pet")
          }

          Response(.notFound) {
            JSONBody("ErrorResponse")
          }
        }
      }
    }

    assertSnapshot(of: try document.jsonValue(), as: .json)
    try OpenAPIValidator.assertValid(document)
  }

  @Test(.snapshots(record: shouldRecord))
  func schemableJSONBodyUsesTypedComponentReference() throws {
    let document = OpenAPIDocument(.v3_1_0) {
      Info(title: "Typed Pet API", version: "1.0.0")

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

    let expectedReference: JSONValue = ["$ref": "#/components/schemas/Pet"]
    #expect(OpenAPISchemaValue.component(Pet.self).jsonValue() == expectedReference)
    assertSnapshot(of: try document.jsonValue(), as: .json)
    try OpenAPIValidator.assertValid(document)
  }

  @Test(.snapshots(record: shouldRecord))
  func binaryResponseSnapshotAndValidation() throws {
    let document = OpenAPIDocument(.v3_1_0) {
      Info(title: "Assets API", version: "1.0.0")

      Components {
        BearerAuth("bearerAuth")
        Schema("ErrorResponse", raw: errorSchema)
      }

      Path("/fonts/{token}/file") {
        GET(operationID: "downloadFontFile") {
          Tags("Fonts")
          Summary("Download font file")
          Security("bearerAuth")
          PathParameter("token")

          Response(.ok, description: "Font file bytes.") {
            Body("font/woff2", schema: .binaryString)
            Body("font/woff", schema: .binaryString)
            Body("font/ttf", schema: .binaryString)
            Body("font/otf", schema: .binaryString)
            Body(.octetStream, schema: .binaryString)
          }

          Response(.unauthorized) {
            JSONBody("ErrorResponse")
          }

          Response(.notFound) {
            JSONBody("ErrorResponse")
          }
        }
      }
    }

    assertSnapshot(of: try document.jsonValue(), as: .json)
    try OpenAPIValidator.assertValid(document)
  }

  @Test
  func canonicalEncodingIsStableAcrossRepeatedCalls() throws {
    let document = petDocument()
    let first = try document.encodeCanonicalJSON()
    let second = try document.encodeCanonicalJSON()

    #expect(first == second)

    let decoded = try JSONValue.parse(first)
    let reencoded = try canonicalEncode(decoded)
    #expect(first == reencoded)
  }

  @Test
  func duplicateOperationIDsFailBeforeEncoding() {
    let document = OpenAPIDocument(.v3_1_0) {
      Info(title: "Invalid API", version: "1.0.0")
      Path("/one") {
        GET(operationID: "duplicate") {
          Response(.ok)
        }
      }
      Path("/two") {
        GET(operationID: "duplicate") {
          Response(.ok)
        }
      }
    }

    #expect(throws: OpenAPIError.duplicateOperationID("duplicate")) {
      try document.jsonValue()
    }
  }

  @Test
  func missingPathParameterFailsBeforeEncoding() {
    let document = OpenAPIDocument(.v3_1_0) {
      Info(title: "Invalid API", version: "1.0.0")
      Path("/pets/{petId}") {
        GET(operationID: "getPetByID") {
          Response(.ok)
        }
      }
    }

    #expect(
      throws: OpenAPIError.missingPathParameter(
        path: "/pets/{petId}",
        parameter: "petId",
        operationID: "getPetByID"
      )
    ) {
      try document.jsonValue()
    }
  }

  private func petDocument() -> OpenAPIDocument {
    OpenAPIDocument(.v3_1_0) {
      Info(title: "Pet API", version: "1.0.0")
      Components {
        Schema("Pet", raw: petSchema)
      }
      Path("/pets") {
        GET(operationID: "listPets") {
          Tags("Pets")
          Response(.ok) {
            JSONBody(schema: .array(.component("Pet")))
          }
        }
      }
    }
  }
}

private let petSchema: JSONValue = [
  "type": "object",
  "required": ["id", "name"],
  "properties": [
    "id": [
      "type": "string",
      "format": "uuid",
    ],
    "name": [
      "type": "string"
    ],
    "tag": [
      "type": "string"
    ],
  ],
]

private let errorSchema: JSONValue = [
  "type": "object",
  "required": ["message"],
  "properties": [
    "message": [
      "type": "string"
    ]
  ],
]

private func canonicalEncode(_ value: JSONValue) throws -> Data {
  var data = try value.serializedData(options: .pretty)
  if data.last != UInt8(ascii: "\n") {
    data.append(UInt8(ascii: "\n"))
  }
  return data
}
