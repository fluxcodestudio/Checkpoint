#!/bin/bash
# Unit Tests: Cron Scheduling Library

# shellcheck source=../test-framework.sh
source "$(dirname "$0")/../test-framework.sh"

# Source the scheduling library we're testing
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$PROJECT_ROOT/lib/features/scheduling.sh"

# ==============================================================================
# _parse_cron_field TESTS
# ==============================================================================

test_suite "_parse_cron_field"

test_case "wildcard - should expand to full range (minutes 0-59)"
result=$(_parse_cron_field "*" 0 59)
# Check first value, last value, and word count
read -ra vals <<< "$result"
if assert_equals "60" "${#vals[@]}" "Should have 60 values" && \
   assert_equals "0" "${vals[0]}" "First value should be 0" && \
   assert_equals "59" "${vals[59]}" "Last value should be 59"; then
    test_pass
else
    test_fail "Got ${#vals[@]} values: ${vals[0]}..${vals[-1]}"
fi

test_case "wildcard - should expand to full range (hours 0-23)"
result=$(_parse_cron_field "*" 0 23)
read -ra vals <<< "$result"
if assert_equals "24" "${#vals[@]}" "Should have 24 values" && \
   assert_equals "0" "${vals[0]}" "First value should be 0" && \
   assert_equals "23" "${vals[23]}" "Last value should be 23"; then
    test_pass
else
    test_fail "Got ${#vals[@]} values: ${vals[0]}..${vals[-1]}"
fi

test_case "wildcard - should expand to full range (dom 1-31)"
result=$(_parse_cron_field "*" 1 31)
read -ra vals <<< "$result"
if assert_equals "31" "${#vals[@]}" "Should have 31 values" && \
   assert_equals "1" "${vals[0]}" "First value should be 1" && \
   assert_equals "31" "${vals[30]}" "Last value should be 31"; then
    test_pass
else
    test_fail "Got ${#vals[@]} values: ${vals[0]}..${vals[-1]}"
fi

test_case "step - */15 minutes should give 0 15 30 45"
result=$(_parse_cron_field "*/15" 0 59)
if assert_equals "0 15 30 45" "$result" "*/15 should expand to 0 15 30 45"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "step - */5 minutes should give 0 5 10 ... 55"
result=$(_parse_cron_field "*/5" 0 59)
expected="0 5 10 15 20 25 30 35 40 45 50 55"
if assert_equals "$expected" "$result" "*/5 should expand correctly"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "step - */2 hours should give 0 2 4 ... 22"
result=$(_parse_cron_field "*/2" 0 23)
expected="0 2 4 6 8 10 12 14 16 18 20 22"
if assert_equals "$expected" "$result" "*/2 hours should expand correctly"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "single value - should return just that value"
result=$(_parse_cron_field "5" 0 59)
if assert_equals "5" "$result" "Single value 5"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "single value 0 - should return 0"
result=$(_parse_cron_field "0" 0 59)
if assert_equals "0" "$result" "Single value 0"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "range - 1-5 should give 1 2 3 4 5"
result=$(_parse_cron_field "1-5" 0 59)
if assert_equals "1 2 3 4 5" "$result" "Range 1-5"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "range - 9-17 should give 9 10 11 ... 17"
result=$(_parse_cron_field "9-17" 0 23)
expected="9 10 11 12 13 14 15 16 17"
if assert_equals "$expected" "$result" "Range 9-17"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "range with step - 9-17/2 should give 9 11 13 15 17"
result=$(_parse_cron_field "9-17/2" 0 23)
if assert_equals "9 11 13 15 17" "$result" "Range with step 9-17/2"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "range with step - 0-23/4 should give 0 4 8 12 16 20"
result=$(_parse_cron_field "0-23/4" 0 23)
if assert_equals "0 4 8 12 16 20" "$result" "Range with step 0-23/4"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "comma list - 1,3,5 should give 1 3 5"
result=$(_parse_cron_field "1,3,5" 0 6)
if assert_equals "1 3 5" "$result" "Comma list 1,3,5"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "comma list - 0,30 should give 0 30"
result=$(_parse_cron_field "0,30" 0 59)
if assert_equals "0 30" "$result" "Comma list 0,30"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "combo - 1-3,5 should give 1 2 3 5"
result=$(_parse_cron_field "1-3,5" 0 6)
if assert_equals "1 2 3 5" "$result" "Combo range+single 1-3,5"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "combo - 0,10-15,30 should give 0 10 11 12 13 14 15 30"
result=$(_parse_cron_field "0,10-15,30" 0 59)
if assert_equals "0 10 11 12 13 14 15 30" "$result" "Combo 0,10-15,30"; then
    test_pass
else
    test_fail "Got: $result"
fi

# ==============================================================================
# _field_contains TESTS
# ==============================================================================

test_suite "_field_contains"

test_case "should find value in list"
if _field_contains "0 15 30 45" 15; then
    test_pass
else
    test_fail "15 should be found in 0 15 30 45"
fi

test_case "should not find missing value"
if ! _field_contains "0 15 30 45" 7; then
    test_pass
else
    test_fail "7 should not be found in 0 15 30 45"
fi

test_case "should find value at start of list"
if _field_contains "0 15 30 45" 0; then
    test_pass
else
    test_fail "0 should be found at start"
fi

test_case "should find value at end of list"
if _field_contains "0 15 30 45" 45; then
    test_pass
else
    test_fail "45 should be found at end"
fi

test_case "should find single value"
if _field_contains "5" 5; then
    test_pass
else
    test_fail "5 should be found in single-element list"
fi

test_case "should use integer comparison (not string)"
if _field_contains "5 10 15" 10; then
    test_pass
else
    test_fail "Integer 10 should match"
fi

# ==============================================================================
# _resolve_schedule TESTS
# ==============================================================================

test_suite "_resolve_schedule"

test_case "@hourly should resolve to '0 * * * *'"
result=$(_resolve_schedule "@hourly")
if assert_equals "0 * * * *" "$result" "@hourly"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "@workhours should resolve to '*/30 9-17 * * 1-5'"
result=$(_resolve_schedule "@workhours")
if assert_equals "*/30 9-17 * * 1-5" "$result" "@workhours"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "@every-5min should resolve to '*/5 * * * *'"
result=$(_resolve_schedule "@every-5min")
if assert_equals "*/5 * * * *" "$result" "@every-5min"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "@daily should resolve to '0 0 * * *'"
result=$(_resolve_schedule "@daily")
if assert_equals "0 0 * * *" "$result" "@daily"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "@weekdays should resolve to '0 * * * 1-5'"
result=$(_resolve_schedule "@weekdays")
if assert_equals "0 * * * 1-5" "$result" "@weekdays"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "@every-30min should resolve to '*/30 * * * *'"
result=$(_resolve_schedule "@every-30min")
if assert_equals "*/30 * * * *" "$result" "@every-30min"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "raw expression should passthrough unchanged"
result=$(_resolve_schedule "*/5 9-17 * * 1-5")
if assert_equals "*/5 9-17 * * 1-5" "$result" "Passthrough"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "wildcard expression should passthrough"
result=$(_resolve_schedule "* * * * *")
if assert_equals "* * * * *" "$result" "Wildcard passthrough"; then
    test_pass
else
    test_fail "Got: $result"
fi

# ==============================================================================
# validate_schedule TESTS
# ==============================================================================

test_suite "validate_schedule"

test_case "valid - standard 5-field expression"
if validate_schedule "*/5 9-17 * * 1-5" 2>/dev/null; then
    test_pass
else
    test_fail "Should accept valid expression"
fi

test_case "valid - all wildcards"
if validate_schedule "* * * * *" 2>/dev/null; then
    test_pass
else
    test_fail "Should accept all wildcards"
fi

test_case "valid - @workhours preset"
if validate_schedule "@workhours" 2>/dev/null; then
    test_pass
else
    test_fail "Should accept @workhours preset"
fi

test_case "valid - @hourly preset"
if validate_schedule "@hourly" 2>/dev/null; then
    test_pass
else
    test_fail "Should accept @hourly preset"
fi

test_case "valid - @daily preset"
if validate_schedule "@daily" 2>/dev/null; then
    test_pass
else
    test_fail "Should accept @daily preset"
fi

test_case "valid - exact time 0 9 * * *"
if validate_schedule "0 9 * * *" 2>/dev/null; then
    test_pass
else
    test_fail "Should accept exact time expression"
fi

test_case "valid - dow with 7 (Sunday alias)"
if validate_schedule "0 * * * 7" 2>/dev/null; then
    test_pass
else
    test_fail "Should accept dow=7 as Sunday alias"
fi

test_case "invalid - only 1 field"
if ! validate_schedule "bad" 2>/dev/null; then
    test_pass
else
    test_fail "Should reject single field"
fi

test_case "invalid - minute > 59"
if ! validate_schedule "99 * * * *" 2>/dev/null; then
    test_pass
else
    test_fail "Should reject minute > 59"
fi

test_case "invalid - hour > 23"
if ! validate_schedule "0 25 * * *" 2>/dev/null; then
    test_pass
else
    test_fail "Should reject hour > 23"
fi

test_case "invalid - dom > 31"
if ! validate_schedule "0 0 32 * *" 2>/dev/null; then
    test_pass
else
    test_fail "Should reject dom > 31"
fi

test_case "invalid - month > 12"
if ! validate_schedule "0 0 * 13 *" 2>/dev/null; then
    test_pass
else
    test_fail "Should reject month > 12"
fi

test_case "invalid - dow > 7"
if ! validate_schedule "0 0 * * 8" 2>/dev/null; then
    test_pass
else
    test_fail "Should reject dow > 7"
fi

test_case "invalid - empty string"
if ! validate_schedule "" 2>/dev/null; then
    test_pass
else
    test_fail "Should reject empty string"
fi

test_case "invalid - 6 fields"
if ! validate_schedule "* * * * * *" 2>/dev/null; then
    test_pass
else
    test_fail "Should reject 6 fields"
fi

test_case "invalid - bad range (start > end)"
if ! validate_schedule "0 20-10 * * *" 2>/dev/null; then
    test_pass
else
    test_fail "Should reject bad range where start > end"
fi

# ==============================================================================
# cron_matches_now TESTS
# ==============================================================================

test_suite "cron_matches_now"

test_case "wildcard - should match any time"
# Inject time: min=30 hour=14 dom=15 month=6 dow=3 (Wed)
if cron_matches_now "* * * * *" "30 14 15 6 3"; then
    test_pass
else
    test_fail "Wildcard should match any time"
fi

test_case "exact time match - 0 9 at 09:00"
if cron_matches_now "0 9 * * *" "0 9 15 6 3"; then
    test_pass
else
    test_fail "Should match at 09:00"
fi

test_case "exact time miss - 0 9 at 10:00"
if ! cron_matches_now "0 9 * * *" "0 10 15 6 3"; then
    test_pass
else
    test_fail "Should NOT match at 10:00"
fi

test_case "exact time miss - 0 9 at 09:01"
if ! cron_matches_now "0 9 * * *" "1 9 15 6 3"; then
    test_pass
else
    test_fail "Should NOT match at 09:01"
fi

test_case "step match - */15 at :00"
if cron_matches_now "*/15 * * * *" "0 10 15 6 3"; then
    test_pass
else
    test_fail "*/15 should match at :00"
fi

test_case "step match - */15 at :15"
if cron_matches_now "*/15 * * * *" "15 10 15 6 3"; then
    test_pass
else
    test_fail "*/15 should match at :15"
fi

test_case "step match - */15 at :30"
if cron_matches_now "*/15 * * * *" "30 10 15 6 3"; then
    test_pass
else
    test_fail "*/15 should match at :30"
fi

test_case "step match - */15 at :45"
if cron_matches_now "*/15 * * * *" "45 10 15 6 3"; then
    test_pass
else
    test_fail "*/15 should match at :45"
fi

test_case "step miss - */15 at :07"
if ! cron_matches_now "*/15 * * * *" "7 10 15 6 3"; then
    test_pass
else
    test_fail "*/15 should NOT match at :07"
fi

test_case "DOW range match - 1-5 on Monday (1)"
if cron_matches_now "* * * * 1-5" "30 10 15 6 1"; then
    test_pass
else
    test_fail "DOW 1-5 should match Monday"
fi

test_case "DOW range match - 1-5 on Friday (5)"
if cron_matches_now "* * * * 1-5" "30 10 15 6 5"; then
    test_pass
else
    test_fail "DOW 1-5 should match Friday"
fi

test_case "DOW range miss - 1-5 on Sunday (0)"
if ! cron_matches_now "* * * * 1-5" "30 10 15 6 0"; then
    test_pass
else
    test_fail "DOW 1-5 should NOT match Sunday"
fi

test_case "DOW range miss - 1-5 on Saturday (6)"
if ! cron_matches_now "* * * * 1-5" "30 10 15 6 6"; then
    test_pass
else
    test_fail "DOW 1-5 should NOT match Saturday"
fi

test_case "DOM/DOW OR logic - both non-wildcard, DOM matches"
# "* * 15 * 1" = 15th of month OR Monday
# Time: 15th, Wednesday(3) -- DOM matches, DOW doesn't
if cron_matches_now "* * 15 * 1" "30 10 15 6 3"; then
    test_pass
else
    test_fail "DOM/DOW OR: should match when DOM matches (15th)"
fi

test_case "DOM/DOW OR logic - both non-wildcard, DOW matches"
# "* * 15 * 1" = 15th OR Monday
# Time: 10th, Monday(1) -- DOW matches, DOM doesn't
if cron_matches_now "* * 15 * 1" "30 10 10 6 1"; then
    test_pass
else
    test_fail "DOM/DOW OR: should match when DOW matches (Monday)"
fi

test_case "DOM/DOW OR logic - both non-wildcard, neither matches"
# "* * 15 * 1" = 15th OR Monday
# Time: 10th, Tuesday(2) -- neither matches
if ! cron_matches_now "* * 15 * 1" "30 10 10 6 2"; then
    test_pass
else
    test_fail "DOM/DOW OR: should NOT match when neither matches"
fi

test_case "DOM/DOW AND logic - DOM wildcard, DOW restricted"
# "* * * * 1-5" = any day, but only weekdays
# Time: Saturday(6) -- DOW doesn't match
if ! cron_matches_now "* * * * 1-5" "30 10 15 6 6"; then
    test_pass
else
    test_fail "DOM wildcard + DOW restricted: should NOT match on Saturday"
fi

test_case "DOM/DOW AND logic - DOM restricted, DOW wildcard"
# "0 9 15 * *" = 9am on the 15th, any DOW
# Time: 15th, any day
if cron_matches_now "0 9 15 * *" "0 9 15 6 3"; then
    test_pass
else
    test_fail "DOM restricted + DOW wildcard: should match on the 15th"
fi

test_case "DOM/DOW AND logic - DOM restricted, DOW wildcard, DOM miss"
# "0 9 15 * *" = 9am on the 15th, any DOW
# Time: 14th
if ! cron_matches_now "0 9 15 * *" "0 9 14 6 3"; then
    test_pass
else
    test_fail "DOM restricted + DOW wildcard: should NOT match on 14th"
fi

test_case "month match"
# Only in January (month=1)
if cron_matches_now "* * * 1 *" "30 10 15 1 3"; then
    test_pass
else
    test_fail "Should match in January"
fi

test_case "month miss"
# Only in January (month=1), current month is June (6)
if ! cron_matches_now "* * * 1 *" "30 10 15 6 3"; then
    test_pass
else
    test_fail "Should NOT match in June when schedule is January-only"
fi

test_case "complex workhours - match within work hours"
# */30 9-17 * * 1-5 = every 30 min, 9am-5pm, weekdays
if cron_matches_now "*/30 9-17 * * 1-5" "30 14 15 6 3"; then
    test_pass
else
    test_fail "Should match 14:30 Wed"
fi

test_case "complex workhours - miss outside hours"
# */30 9-17 * * 1-5 at 18:30 Wed
if ! cron_matches_now "*/30 9-17 * * 1-5" "30 18 15 6 3"; then
    test_pass
else
    test_fail "Should NOT match 18:30 (outside work hours)"
fi

test_case "complex workhours - miss on weekend"
# */30 9-17 * * 1-5 at 10:00 Saturday(6)
if ! cron_matches_now "*/30 9-17 * * 1-5" "0 10 15 6 6"; then
    test_pass
else
    test_fail "Should NOT match on Saturday"
fi

test_case "complex workhours - miss at wrong minute"
# */30 9-17 * * 1-5 at 14:15 Wed (15 is not in */30)
if ! cron_matches_now "*/30 9-17 * * 1-5" "15 14 15 6 3"; then
    test_pass
else
    test_fail "Should NOT match at :15 for */30"
fi

# ==============================================================================
# next_cron_match TESTS
# ==============================================================================

test_suite "next_cron_match"

test_case "hourly from :15 - should find next :00"
result=$(next_cron_match "0 * * * *" "15 9 15 6 3")
if assert_contains "$result" "45" "Should be 45 minutes until next match"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "every-5min from :07 - should find :10 (3 min away)"
result=$(next_cron_match "*/5 * * * *" "7 9 15 6 3")
if assert_contains "$result" "3" "Should be 3 minutes until :10"; then
    test_pass
else
    test_fail "Got: $result"
fi

test_case "should return 0 when already matching"
result=$(next_cron_match "*/15 * * * *" "0 9 15 6 3")
if assert_contains "$result" "0" "Should be 0 minutes when already matching"; then
    test_pass
else
    test_fail "Got: $result"
fi

# ==============================================================================
# SUMMARY
# ==============================================================================

print_test_summary
