#!/usr/bin/env bash
# Run the offline ocp test suite. No network required.
#
#   tests/run.sh                 # test the ocp next to this directory
#   OCP=/path/to/ocp tests/run.sh
set -u
cd "$(dirname "$0")"

total_fail=0
for t in test_*.sh; do
  echo "######## $t ########"
  if bash "$t"; then :; else total_fail=$((total_fail+1)); fi
  echo
done

if [ "$total_fail" -eq 0 ]; then
  echo "ALL SUITES PASSED"
else
  echo "$total_fail SUITE(S) FAILED"
fi
[ "$total_fail" -eq 0 ]
