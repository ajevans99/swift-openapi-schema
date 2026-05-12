#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target_dir="${repo_root}/Sources/OpenAPISchema/Resources/MetaSchemas"

mkdir -p "${target_dir}"
curl -fsSL "https://spec.openapis.org/oas/3.1/schema/2025-09-15" \
  -o "${target_dir}/openapi-3.1-2025-09-15.schema.json"
curl -fsSL "https://json-schema.org/draft/2020-12/schema" \
  -o "${target_dir}/json-schema-draft-2020-12.schema.json"

shasum -a 256 "${target_dir}"/*.json
