#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="${repo_root}/Sources/OpenAPISchema/Resources/MetaSchemas"

mkdir -p "${target_dir}"
curl -fsSL "https://spec.openapis.org/oas/3.1/schema/2025-09-15" \
  -o "${target_dir}/openapi-3.1-2025-09-15.schema.json"
curl -fsSL "https://json-schema.org/draft/2020-12/schema" \
  -o "${target_dir}/json-schema-draft-2020-12.schema.json"

for vocabulary in core applicator unevaluated validation meta-data format-annotation content; do
  curl -fsSL "https://json-schema.org/draft/2020-12/meta/${vocabulary}" \
    -o "${target_dir}/json-schema-draft-2020-12-meta-${vocabulary}.schema.json"
done

for example in non-oauth-scopes webhook-example; do
  curl -fsSL \
    "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/69d8b7953c3259e243cf746388a0951b89649763/examples/v3.1/${example}.json" \
    -o "${target_dir}/openapi-3.1-example-${example}.json"
done

curl -fsSL \
  "https://raw.githubusercontent.com/OAI/OpenAPI-Specification/c9f8f040e825a827bb011955bd41b7e2d899688f/LICENSE" \
  -o "${target_dir}/LICENSE-OpenAPI.txt"
curl -fsSL \
  "https://raw.githubusercontent.com/json-schema-org/json-schema-spec/4f56a9900674b27804f0ec32e3b7fdfa4efad695/LICENSE" \
  -o "${target_dir}/LICENSE-JSON-Schema.txt"

(
  cd "${target_dir}"
  shasum -a 256 ./*.json ./LICENSE-*.txt > SHA256SUMS
  shasum -a 256 -c SHA256SUMS
)
