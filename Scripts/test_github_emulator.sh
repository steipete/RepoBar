#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${GITHUB_EMULATOR_PORT:-4101}"
BASE_URL="http://127.0.0.1:${PORT}"
TOKEN="gho_test_token_admin"
LOG_FILE="$(mktemp -t repobar-github-emulator.XXXXXX.log)"

cleanup() {
  if [[ -n "${EMULATOR_PID:-}" ]] && kill -0 "${EMULATOR_PID}" >/dev/null 2>&1; then
    kill "${EMULATOR_PID}" >/dev/null 2>&1 || true
    wait "${EMULATOR_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

echo "==> Starting GitHub emulator on ${BASE_URL}"
pnpm dlx emulate@0.5.0 start \
  --service github \
  --port "${PORT}" \
  --seed "${ROOT}/Scripts/emulate-github-ci.yaml" \
  >"${LOG_FILE}" 2>&1 &
EMULATOR_PID="$!"

for _ in $(seq 1 60); do
  if curl -fsS "${BASE_URL}/user" \
    -H "Authorization: Bearer ${TOKEN}" \
    >/dev/null 2>&1; then
    break
  fi

  if ! kill -0 "${EMULATOR_PID}" >/dev/null 2>&1; then
    cat "${LOG_FILE}" >&2
    exit 1
  fi

  sleep 1
done

if ! curl -fsS "${BASE_URL}/user" \
  -H "Authorization: Bearer ${TOKEN}" \
  >/dev/null 2>&1; then
  cat "${LOG_FILE}" >&2
  echo "GitHub emulator did not become ready." >&2
  exit 1
fi

export GITHUB_TOKEN="${TOKEN}"
export GITHUB_API="${BASE_URL}"

echo "==> Checking repository lookup against emulator"
pnpm -s ghrest repo octocat/hello-world --json | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const repo = JSON.parse(input);
  if (repo.full_name !== "octocat/hello-world") {
    throw new Error(`unexpected repo ${repo.full_name}`);
  }
});
'

echo "==> Checking Actions run lookup against emulator"
pnpm -s ghrest ci octocat/hello-world --branch main --json | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const body = JSON.parse(input);
  if (!Array.isArray(body.workflow_runs)) {
    throw new Error("workflow_runs must be an array");
  }
});
'

echo "==> Creating and reading a release through emulator"
node -e '
const [base, token] = process.argv.slice(1);
const response = await fetch(`${base}/repos/octocat/hello-world/releases`, {
  method: "POST",
  headers: {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "Content-Type": "application/json",
    "User-Agent": "RepoBar-CI",
  },
  body: JSON.stringify({
    tag_name: "v1.0.0",
    name: "v1.0.0",
    body: "fixture release",
  }),
});
if (response.status !== 201) {
  throw new Error(`release create failed with HTTP ${response.status}: ${await response.text()}`);
}
' "${BASE_URL}" "${TOKEN}"

pnpm -s ghrest release octocat/hello-world --json | node -e '
let input = "";
process.stdin.on("data", chunk => input += chunk);
process.stdin.on("end", () => {
  const releases = JSON.parse(input);
  if (!Array.isArray(releases) || releases[0]?.tag_name !== "v1.0.0") {
    throw new Error("expected v1.0.0 release from emulator");
  }
});
'

echo "==> Checking missing repository fails"
if pnpm -s ghrest repo octocat/missing --json >/tmp/repobar-ghrest-missing.out 2>&1; then
  cat /tmp/repobar-ghrest-missing.out >&2
  echo "Expected missing repository lookup to fail." >&2
  exit 1
fi

echo "OK: GitHub emulator smoke test passed."
