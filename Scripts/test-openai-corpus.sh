#!/usr/bin/env bash
set -euo pipefail

# Keep this optional multi-megabyte acceptance fixture out of the package resources.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture_dir="${1:?Usage: Scripts/test-openai-corpus.sh /absolute/artifact/directory}"
revision="4bb21ba8e9213c3d955b69dc3f76dd7537439828"
mkdir -p "${fixture_dir}"
curl -fsSL "https://raw.githubusercontent.com/openai/openai-openapi/${revision}/openapi.json" \
  -o "${fixture_dir}/openapi.json"
curl -fsSL "https://raw.githubusercontent.com/openai/openai-openapi/${revision}/LICENSE" \
  -o "${fixture_dir}/LICENSE"
(
  cd "${fixture_dir}"
  printf '%s\n' \
    '3d6223349eadfd937624b9e6b8abf596ec2f680a1a367889cf6a6f924e568127  openapi.json' \
    'bcba3de214851cce46ed5af42d6698044616eeace887c3231bc7a20474ab639e  LICENSE' \
    | shasum -a 256 -c -
)
fixture_path="$(cd "${fixture_dir}" && pwd)/openapi.json"
cd "${repo_root}"
OPENAPI_CORPUS_PATH="${fixture_path}" swift test --filter 'OpenAPIImportTests|OpenAPIValidatorTests'
