import Foundation
import OpenAPISchema
import OrderedJSON
import Testing

struct OpenAPIImportTests {
  private let sourceURI = URL(string: "https://example.test/spec/openapi.json")!

  @Test func rawRoundTripPreservesUnknownFieldsAndNumberTokens() throws {
    let data = Data(
      #"""
      {
        "openapi": "3.1.1",
        "info": {"title": "Import", "version": "1"},
        "paths": {},
        "components": {"schemas": {
          "Raw": {
            "$id": "models/raw.json", "$ref": "#anchor", "nullable": true,
            "minimum": 9007199254740993123456789,
            "default": {"tiny": 1e-9999, "huge": 1E+9999, "negativeZero": -0.00},
            "x-custom": {"not-a-schema": {"$ref": "https://must-not-load.test"}}
          },
          "Anything": true
        }},
        "webhooks": {"received": {"post": {"responses": {"204": {"description": "OK"}}}}},
        "x-vendor": {"ref": "#/untouched", "future": [null, false]},
        "unknownFutureField": {"arbitrary": "preserved"}
      }
      """#.utf8)
    let document = try OpenAPIJSONDocument(data: data, sourceURI: sourceURI)
    #expect(document.rawValue == (try JSONValue.parse(data)))
    #expect(document.sourceURI == sourceURI)
    #expect(document.version == "3.1.1")
    for pretty in [false, true] {
      let encoded = try document.encodeJSON(prettyPrinted: pretty)
      #expect(try JSONValue.parse(encoded) == document.rawValue)
      let text = String(decoding: encoded, as: UTF8.self)
      for token in ["9007199254740993123456789", "1e-9999", "1E+9999", "-0.00"] {
        #expect(text.contains(token))
      }
    }
    let schemas = try document.componentSchemas()
    #expect(schemas.count == 2)
    #expect(schemas["Anything"]?.value == .boolean(true))
    #expect(schemas["Raw"]?.location.pointer == "/components/schemas/Raw")
    #expect(try document.operations().isEmpty)
  }

  @Test func authoredRepresentationPreservesRawSchemaTokensAndBuilderOutput() throws {
    let schema = try JSONValue.parse(#"{"default":1.000e+42,"x-raw":{"$ref":"unresolved.json"}}"#)
    let authored = OpenAPIDocument {
      Info(title: "Authoring", version: "1")
      Components { Schema("Raw", raw: schema) }
    }
    let shared = try authored.documentRepresentation(sourceURI: sourceURI)
    #expect(shared.rawValue == (try authored.jsonValue()))
    #expect(try shared.componentSchemas()["Raw"]?.value == schema)
    #expect(String(decoding: try shared.encodeJSON(), as: UTF8.self).contains("1.000e+42"))
  }

  @Test func parameterSecurityAndServerInheritance() throws {
    let document = try parse(
      #"""
      {
        "openapi":"3.1.0",
        "servers":[{"url":"https://root.test"}],
        "security":[{"oauth":["read"],"apiKey":[]}],
        "components":{"parameters":{
          "ID":{"name":"id","in":"path","required":true,"schema":{"type":"string"}},
          "Search":{"name":"q","in":"query","schema":{"type":"string"}}
        }},
        "paths":{"/items/{id}":{
          "servers":[{"url":"https://path.test/{v}","variables":{"v":{"default":"v1"}}}],
          "parameters":[{"$ref":"#/components/parameters/ID"},{"$ref":"#/components/parameters/Search"}],
          "get":{
            "operationId":"getItem",
            "parameters":[
              {"name":"q","in":"query","required":true,"schema":{"type":"integer"}},
              {"name":"q","in":"header","schema":{"type":"string"}}
            ],
            "responses":{"200":{"description":"OK","content":{
              "application/json":{"schema":{"$ref":"#/components/schemas/Item"}},
              "text/event-stream":{"schema":{"type":"string"}},
              "application/octet-stream":{}
            }},"2XX":{"description":"Other success"},"default":{"description":"Error"}}
          },
          "post":{
            "security":[],"servers":[],
            "requestBody":{"required":true,"content":{"multipart/form-data":{
              "schema":{"type":"object"},"encoding":{"file":{"contentType":"application/octet-stream"}}
            }}},
            "responses":{"204":{"description":"OK"}}
          },
          "delete":{"security":[{}],"responses":{"204":{"description":"OK"}}}
        }}
      }
      """#)
    let operations = try document.operations()
    #expect(operations.map(\.method) == ["get", "post", "delete"])
    let get = try #require(operations.first)
    #expect(get.path == "/items/{id}")
    #expect(get.operationID == "getItem")
    #expect(get.source.location.pointer == "/paths/~1items~1{id}/get")
    #expect(get.parameters.map(\.name) == ["id", "q", "q"])
    #expect(get.parameters.map(\.location) == ["path", "query", "header"])
    #expect(get.parameters[0].source.location.pointer == "/paths/~1items~1{id}/parameters/0")
    #expect(get.parameters[0].target.location.pointer == "/components/parameters/ID")
    #expect(get.parameters[1].required)
    #expect(
      get.parameters[1].schema?.location.pointer == "/paths/~1items~1{id}/get/parameters/0/schema")
    #expect(get.security == [try document.value(at: "/security/0")])
    #expect(get.servers == [try document.value(at: "/paths/~1items~1{id}/servers/0")])
    #expect(get.responses.map(\.status) == ["200", "2XX", "default"])
    #expect(
      get.responses[0].content.map(\.mediaType) == [
        "application/json", "text/event-stream", "application/octet-stream",
      ])
    #expect(get.responses[0].content[0].schema?.value == ["$ref": "#/components/schemas/Item"])
    #expect(get.responses[0].content[2].schema == nil)
    #expect(operations[1].operationID == nil)
    #expect(operations[1].security.isEmpty)
    #expect(operations[1].servers.isEmpty)
    #expect(operations[1].requestBody?.required == true)
    #expect(operations[1].requestBody?.content.first?.mediaType == "multipart/form-data")
    #expect(operations[2].security.map(\.value) == [[:]])
  }

  @Test func externalReferencesRetainOriginalSchemaScope() throws {
    let externalURI = URL(string: "https://example.test/spec/shared.json")!
    let raw = try JSONValue.parse(
      #"""
      {
        "parameters":{"P":{"name":"filter","in":"query","content":{
          "application/json":{"schema":{"$ref":"models.json#/$defs/Filter"}}
        }}},
        "bodies":{"B":{"content":{"application/json":{"schema":{"$ref":"models.json#/$defs/Body"}}}}},
        "responses":{"R":{"description":"Target","content":{
          "application/json":{"schema":{"$ref":"#/schemas/Result"}}
        }}},
        "schemas":{"Result":{"type":"string"}},
        "pathItem":{"get":{
          "parameters":[{"$ref":"#/parameters/P"}],
          "requestBody":{"$ref":"#/bodies/B"},
          "responses":{"200":{"$ref":"#/responses/R","description":"Override","x-source":true}}
        }}
      }
      """#)
    let document = try OpenAPIJSONDocument(
      data: Data(
        #"{"openapi":"3.1.0","paths":{"/external":{"$ref":"shared.json#/pathItem"}}}"#.utf8),
      sourceURI: sourceURI, externalDocuments: [externalURI: raw])
    let operation = try #require(document.operations().first)
    #expect(operation.pathItem.location.sourceURI == sourceURI)
    #expect(operation.source.location == .init(sourceURI: externalURI, pointer: "/pathItem/get"))
    #expect(operation.parameters[0].schema == nil)
    #expect(
      operation.parameters[0].content[0].schema?.location
        == .init(
          sourceURI: externalURI, pointer: "/parameters/P/content/application~1json/schema"))
    #expect(operation.requestBody?.content[0].schema?.location.sourceURI == externalURI)
    let response = try #require(operation.responses.first)
    #expect(try response.source.member("description")?.value == "Override")
    #expect(try response.target.member("description")?.value == "Target")
    #expect(response.content[0].schema?.value == ["$ref": "#/schemas/Result"])
    #expect(response.content[0].schema?.location.sourceURI == externalURI)
    #expect(try document.encodeJSON() == document.rawValue.serializedData())
  }

  @Test func escapedAndPercentEncodedReferencePointers() throws {
    let document = try parse(
      #"""
      {"openapi":"3.1.0","components":{"responses":{
        "a/b~c space":{"description":"Escaped"},
        "Chain":{"$ref":"#/components/responses/a~1b~0c%20space"}
      }},"paths":{"/":{"get":{"responses":{"200":{"$ref":"#/components/responses/Chain"}}}}},
       "x-values":[{"":42}]}
      """#)
    let response = try #require(document.operations().first?.responses.first)
    #expect(response.target.location.pointer == "/components/responses/a~1b~0c space")
    #expect(try document.value(at: "/x-values/0/").value == 42)
    for pointer in ["/x-values/00", "/x-values/-", "/x-values/2", "/x-values/0/~2", "x-values"] {
      #expect(throws: OpenAPIImportError.self) { try document.value(at: pointer) }
    }
  }

  @Test(arguments: [
    #"{"$ref":"https://unprovided.invalid/responses.json#/R"}"#,
    ##"{"$ref":"#/components/responses/Missing"}"##,
    ##"{"$ref":"#anchor"}"##,
    ##"{"$ref":"#/components/responses/Cycle"}"##,
    #"{"$ref":42}"#,
  ])
  func referenceFailuresAreLocatedAndNeverFetch(_ response: String) throws {
    let document = try parse(
      """
      {"openapi":"3.1.0","components":{"responses":{"Cycle":{"$ref":"#/components/responses/Cycle"}}},
       "paths":{"/":{"get":{"responses":{"200":\(response)}}}}}
      """)
    do {
      _ = try document.operations()
      Issue.record("Expected checked reference resolution to fail.")
    } catch let error as OpenAPIImportError {
      #expect(error.location.sourceURI == sourceURI)
      #expect(error.location.pointer.contains("responses"))
      #expect(!error.message.isEmpty)
    }
  }

  @Test(arguments: [
    (#"{"parameters":{},"responses":{"200":{"description":"OK"}}}"#, "/parameters"),
    (
      #"{"parameters":[{"name":"x","in":"query","schema":false},{"name":"x","in":"query","schema":true}],"responses":{"200":{"description":"OK"}}}"#,
      "/parameters/1"
    ),
    (
      #"{"parameters":[{"name":"id","in":"path","schema":true}],"responses":{"200":{"description":"OK"}}}"#,
      "/parameters/0"
    ),
    (
      #"{"parameters":[{"name":"x","in":"query","schema":true,"content":{}}],"responses":{"200":{"description":"OK"}}}"#,
      "/parameters/0"
    ),
    (
      #"{"requestBody":{"content":[]},"responses":{"200":{"description":"OK"}}}"#,
      "/requestBody/content"
    ),
    (
      #"{"responses":{"200":{"description":"OK","content":{"application/json":{"schema":3}}}}}"#,
      "/responses/200/content/application~1json/schema"
    ),
    (#"{"security":{},"responses":{"200":{"description":"OK"}}}"#, "/security"),
    (#"{"security":[{"key":[3]}],"responses":{"200":{"description":"OK"}}}"#, "/security/0/key/0"),
    (#"{"servers":[{"url":false}],"responses":{"200":{"description":"OK"}}}"#, "/servers/0/url"),
    (#"{"responses":{"600":{"description":"Bad"}}}"#, "/responses/600"),
    (#"{"responses":{"200":{"description":3}}}"#, "/responses/200/description"),
    (#"{"responses":{}}"#, "/responses"),
  ])
  func checkedShapeErrorsRetainLocation(_ operation: String, _ suffix: String) throws {
    let document = try parse(#"{"openapi":"3.1.0","paths":{"/":{"get":\#(operation)}}}"#)
    do {
      _ = try document.operations()
      Issue.record("Expected an explicit shape failure.")
    } catch let error as OpenAPIImportError {
      #expect(error.location.pointer == "/paths/~1/get\(suffix)")
    }
  }

  @Test func parsingAndCheckedViewsRemainSeparate() throws {
    let document = try parse(
      #"{"openapi":"3.1.0","info":false,"paths":null,"components":{"schemas":{"X":7}}}"#)
    #expect(try document.value(at: "/info").value == false)
    #expect(throws: OpenAPIImportError.self) { try document.operations() }
    #expect(throws: OpenAPIImportError.self) { try document.componentSchemas() }
    for text in ["[]", "{}", #"{"openapi":31}"#, #"{"openapi":"3.0.3"}"#, #"{"openapi":"3.1.x"}"#] {
      #expect(throws: OpenAPIImportError.self) { try parse(text) }
    }
    #expect(throws: JSONParseError.self) { try parse(#"{"openapi":"3.1.0",}"#) }
  }

  @Test func pathItemSiblingMergeIsNeverInvented() throws {
    let document = try parse(
      #"""
      {"openapi":"3.1.0","components":{"pathItems":{"P":{"get":{"responses":{"200":{"description":"OK"}}}}}},
       "paths":{"/":{"$ref":"#/components/pathItems/P","get":{"responses":{"201":{"description":"Conflict"}}}}}}
      """#)
    do {
      _ = try document.operations()
      Issue.record("Expected unsupported Path Item merge.")
    } catch let error as OpenAPIImportError {
      #expect(error.location.pointer == "/paths/~1/$ref")
      #expect(error.message.contains("ambiguous"))
    }
  }

  @Test func duplicateOperationIDsAreReported() throws {
    let document = try parse(
      #"""
      {"openapi":"3.1.0","paths":{"/":{
        "get":{"operationId":"same","responses":{"200":{"description":"OK"}}},
        "post":{"operationId":"same","responses":{"200":{"description":"OK"}}}
      }}}
      """#)
    #expect(throws: OpenAPIImportError.self) { try document.operations() }
  }

  @Test func retrievalURIsMustBeExplicitAndUnambiguous() throws {
    #expect(throws: OpenAPIImportError.self) {
      try OpenAPIJSONDocument(
        rawValue: ["openapi": "3.1.0"], sourceURI: URL(string: "relative.json"))
    }
    #expect(throws: OpenAPIImportError.self) {
      try OpenAPIJSONDocument(
        rawValue: ["openapi": "3.1.0"], sourceURI: sourceURI,
        externalDocuments: [sourceURI: [:]])
    }
    let noBase = try OpenAPIJSONDocument(
      rawValue: ["openapi": "3.1.0", "ref": ["$ref": "relative.json#/R"]])
    #expect(throws: OpenAPIImportError.self) {
      try noBase.resolveReferenceObject(noBase.value(at: "/ref"))
    }
  }

  @Test func referencesCanReturnToRootAndResolveWithoutARetrievalURI() throws {
    let externalURI = URL(string: "https://example.test/shared/refs.json")!
    let external: JSONValue = [
      "R": ["$ref": "../spec/openapi.json#/components/responses/R"]
    ]
    let document = try OpenAPIJSONDocument(
      rawValue: [
        "openapi": "3.1.0",
        "components": ["responses": ["R": ["description": "Root"]]],
        "reference": ["$ref": "../shared/refs.json#/R"],
      ], sourceURI: sourceURI, externalDocuments: [externalURI: external])
    let target = try document.resolveReferenceObject(document.value(at: "/reference"))
    #expect(target.location == .init(sourceURI: sourceURI, pointer: "/components/responses/R"))
    let anonymous = try OpenAPIJSONDocument(
      rawValue: [
        "openapi": "3.1.0", "target": ["description": "Local"],
        "reference": ["$ref": "#/target"],
      ])
    #expect(
      try anonymous.resolveReferenceObject(anonymous.value(at: "/reference")).location
        == .init(pointer: "/target"))
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["OPENAPI_CORPUS_PATH"] != nil))
  func pinnedOpenAICorpusImportAndExport() throws {
    let path = try #require(ProcessInfo.processInfo.environment["OPENAPI_CORPUS_PATH"])
    let data = try Data(contentsOf: URL(fileURLWithPath: path))
    let document = try OpenAPIJSONDocument(
      data: data,
      sourceURI: URL(
        string:
          "https://raw.githubusercontent.com/openai/openai-openapi/4bb21ba8e9213c3d955b69dc3f76dd7537439828/openapi.json"
      ))
    #expect(document.version == "3.1.0")
    #expect(document.rawValue == (try JSONValue.parse(data)))
    #expect(try JSONValue.parse(document.encodeJSON()) == document.rawValue)
    #expect(try document.value(at: "/paths").value.object?.count == 215)
    #expect(try document.componentSchemas().count == 1852)
    #expect(try document.operations().count == 338)
  }

  private func parse(_ text: String) throws -> OpenAPIJSONDocument {
    try OpenAPIJSONDocument(data: Data(text.utf8), sourceURI: sourceURI)
  }
}
