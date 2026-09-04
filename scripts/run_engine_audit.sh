#!/bin/bash
# One reproducible command for the Phase 1 engine hardening evidence.
#
# Runs, in order, with fail-fast (`set -euo pipefail` plus an explicit check
# after each step): shared-data referential integrity, the full Python audit
# test suite, the five Task-4 focused Swift suites, the semantic golden diff
# against HEAD (must be clean — nothing here should have changed engine
# behavior), the surfaced-input-contract audit, and the recommendation-trace
# audit. Stops at the first failure so a broken step never gets buried under
# later, unrelated output.
#
#   scripts/run_engine_audit.sh
#
# Run from anywhere; paths are resolved relative to the repo root. Requires
# python3, xcodebuild, and an "iPhone 17 Pro" simulator (any OS runtime) to
# be available — override the destination with PACKWISE_SIM_DESTINATION if
# a different simulator should be used.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

SIM_DESTINATION="${PACKWISE_SIM_DESTINATION:-platform=iOS Simulator,name=iPhone 17 Pro}"

# The five Swift test suites Task 4 added invariant/authority/failure
# coverage to. Not the full PackWiseTests suite — the plan asks for the
# focused suites this hardening arc actually touched.
FOCUSED_SWIFT_SUITES=(
    PackWiseTests/ClothingQuantityTests
    PackWiseTests/ConstraintTests
    PackWiseTests/IntelligenceServiceTests
    PackWiseTests/ContextIntelligenceGateTests
    PackWiseTests/WeatherChangeTests
)

step() {
    echo ""
    echo "==> $1"
}

step "1/6  Shared data referential integrity (scripts/validate_shared.py)"
python3 scripts/validate_shared.py

step "2/6  Python audit test suite (scripts/tests)"
python3 -m unittest discover -s scripts/tests

step "3/6  Focused Swift suites (Task 4 invariant/authority/failure audits)"
ONLY_TESTING_ARGS=()
for suite in "${FOCUSED_SWIFT_SUITES[@]}"; do
    ONLY_TESTING_ARGS+=("-only-testing:${suite}")
done
xcodebuild test \
    -project ios/PackWise.xcodeproj \
    -scheme PackWise \
    -destination "$SIM_DESTINATION" \
    "${ONLY_TESTING_ARGS[@]}"

step "4/6  Semantic golden diff against HEAD (scripts/report_engine_goldens.py)"
python3 scripts/report_engine_goldens.py \
    --baseline-ref HEAD \
    --candidate ios/PackWiseTests/Goldens

step "5/6  Surfaced-input contract audit (scripts/audit_engine_inputs.py)"
python3 scripts/audit_engine_inputs.py \
    --contracts docs/engine-audits/surfaced-input-contracts.json \
    --format markdown

step "6/6  Recommendation-trace audit (scripts/audit_recommendation_traces.py)"
python3 scripts/audit_recommendation_traces.py \
    --goldens ios/PackWiseTests/Goldens \
    --format markdown --strict

echo ""
echo "All engine audit steps passed."
