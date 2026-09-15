# Offline OpenAPI validation resources

These files are unmodified upstream documents, retrieved on 2026-09-15.
`SHA256SUMS` records SHA-256 checksums of every downloaded JSON and license file.
From this directory, verify with `shasum -a 256 -c SHA256SUMS`.

## Provenance and licensing

| Local file | Source |
| --- | --- |
| `openapi-3.1-2025-09-15.schema.json` | <https://spec.openapis.org/oas/3.1/schema/2025-09-15> |
| `json-schema-draft-2020-12.schema.json` | <https://json-schema.org/draft/2020-12/schema> |
| `json-schema-draft-2020-12-meta-core.schema.json` | <https://json-schema.org/draft/2020-12/meta/core> |
| `json-schema-draft-2020-12-meta-applicator.schema.json` | <https://json-schema.org/draft/2020-12/meta/applicator> |
| `json-schema-draft-2020-12-meta-unevaluated.schema.json` | <https://json-schema.org/draft/2020-12/meta/unevaluated> |
| `json-schema-draft-2020-12-meta-validation.schema.json` | <https://json-schema.org/draft/2020-12/meta/validation> |
| `json-schema-draft-2020-12-meta-meta-data.schema.json` | <https://json-schema.org/draft/2020-12/meta/meta-data> |
| `json-schema-draft-2020-12-meta-format-annotation.schema.json` | <https://json-schema.org/draft/2020-12/meta/format-annotation> |
| `json-schema-draft-2020-12-meta-content.schema.json` | <https://json-schema.org/draft/2020-12/meta/content> |

The OpenAPI schema and the two imported example fixtures are distributed under
Apache-2.0; the unchanged upstream license is `LICENSE-OpenAPI.txt`, retrieved from
[OpenAPI-Specification at c9f8f040e825a827bb011955bd41b7e2d899688f](https://github.com/OAI/OpenAPI-Specification/blob/c9f8f040e825a827bb011955bd41b7e2d899688f/LICENSE).

The example files are unchanged copies from OpenAPI-Specification tag `3.1.1`,
commit `69d8b7953c3259e243cf746388a0951b89649763`:

- `openapi-3.1-example-non-oauth-scopes.json`:
  [examples/v3.1/non-oauth-scopes.json](https://github.com/OAI/OpenAPI-Specification/blob/69d8b7953c3259e243cf746388a0951b89649763/examples/v3.1/non-oauth-scopes.json)
- `openapi-3.1-example-webhook-example.json`:
  [examples/v3.1/webhook-example.json](https://github.com/OAI/OpenAPI-Specification/blob/69d8b7953c3259e243cf746388a0951b89649763/examples/v3.1/webhook-example.json)

JSON Schema documents are Copyright (c) 2022 JSON Schema Specification Authors.
`LICENSE-JSON-Schema.txt` preserves the upstream BSD-3-Clause and Academic Free
License 3.0 text verbatim, retrieved from
[json-schema-spec at 4f56a9900674b27804f0ec32e3b7fdfa4efad695](https://github.com/json-schema-org/json-schema-spec/blob/4f56a9900674b27804f0ec32e3b7fdfa4efad695/LICENSE).

## Validation boundary and regression evidence

`OpenAPIValidator` uses the original OpenAPI schema and explicitly registers the
Draft 2020-12 root plus all seven `meta/*` documents above. Runtime validation
does not download anything. The example fixtures are regression inputs, not
registered schemas.

With published `swift-json-schema` **0.14.0**
(`88abaf2e821f55f7c3c04eb53385b3c0dd2fbf8f`), the untouched schema passes the
seven existing authored-document tests and both official imported examples.
Unknown root and Info Object properties fail `unevaluatedProperties`; a License
Object with both `identifier` and `url` fails `dependentSchemas`/`not`; a path
parameter with `style: "form"` fails `dependentSchemas`/`enum`. Regression tests
demonstrate that the former recursively stripped schema incorrectly accepted
all four invalid cases. Neither keyword is stripped in production anymore.
The original OpenAPI schema and Draft 2020-12 root retain their previous bytes
and checksums.

The separate, opt-in `pinnedOpenAICorpusStructuralValidation` test also passes
against the unmodified OpenAI corpus at commit
`4bb21ba8e9213c3d955b69dc3f76dd7537439828` (215 paths, 338 operations, 1,852
component schemas), without evaluation errors. This large fixture is not bundled
here. Use the repository's `Scripts/test-openai-corpus.sh` to retrieve and verify
it, then run the validator test with `OPENAPI_CORPUS_PATH` pointing at the
downloaded `openapi.json`.

The OpenAPI schema describes itself as **without Schema Object validation**.
It checks OpenAPI structure, including that embedded Schema Objects are objects
or booleans, but does not validate their keyword syntax, `$schema` dialect
semantics, or application instances. It is not a complete validator of every
normative OpenAPI rule. Source `$ref` and `$dynamicRef` values are instance data:
they are not dereferenced, rewritten, fetched, or registered as validation
schemas. Parsing and checked source views are separate from this validation.

## Updates

Run `bash Scripts/update-meta-schemas.sh` from the repository root only when
intentionally refreshing vendored upstream resources. It is the explicit
network-enabled maintenance step; it also downloads the pinned licenses and
examples and regenerates `SHA256SUMS`. Review the downloaded diffs and update the
retrieval date here before accepting an update. No formatting or keyword
transformations should be applied to the downloaded JSON.
