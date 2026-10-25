#!/usr/bin/env bash
set -Eeuo pipefail

# Disposable PostgreSQL 17 concurrency audit. This script creates and removes
# its own ephemeral Docker container. It never connects to Supabase or another DB.

if ! command -v docker >/dev/null 2>&1; then
  echo "ERROR: Docker is required. No database was started or changed." >&2
  exit 2
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SQL_FILE="$SCRIPT_DIR/s6-6-postgres17-locking-audit.sql"
CONTAINER="thuscene-s66-pg17-$$"
TMP_DIR="$(mktemp -d)"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

if [[ ! -f "$SQL_FILE" ]]; then
  echo "ERROR: SQL fixture not found: $SQL_FILE" >&2
  exit 2
fi

echo "Starting disposable PostgreSQL 17 container: $CONTAINER"
docker run --detach --rm --name "$CONTAINER" \
  --env POSTGRES_PASSWORD=local_test_only \
  --env POSTGRES_DB=s66_test \
  postgres:17-alpine >/dev/null

ready=0
for _ in $(seq 1 60); do
  if docker exec "$CONTAINER" pg_isready -U postgres -d s66_test >/dev/null 2>&1; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" != 1 ]]; then
  echo "ERROR: PostgreSQL 17 did not become ready." >&2
  docker logs "$CONTAINER" >&2 || true
  exit 2
fi

psql_db() {
  docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d s66_test "$@"
}

reset_fixture() {
  psql_db <<'SQL'
TRUNCATE attendance_route_occurrences, attendance_routes, event_occurrences, events CASCADE;
INSERT INTO events(id, name) VALUES
('00000000-0000-0000-0000-000000000001', 'Event A'),
('00000000-0000-0000-0000-000000000002', 'Event B');
INSERT INTO attendance_routes(id, event_id, name) VALUES
('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000001', 'Route R');
INSERT INTO event_occurrences(id, event_id, name) VALUES
('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000001', 'Occurrence O');
SQL
}

expect_fail() {
  local label="$1"; shift
  local expected_pattern="$1"; shift
  local logfile="$TMP_DIR/${label//[^a-zA-Z0-9_-]/_}.log"
  set +e
  "$@" >"$logfile" 2>&1
  local status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    echo "FAIL: $label unexpectedly succeeded" >&2
    cat "$logfile" >&2
    exit 1
  fi
  if ! grep -Eq "$expected_pattern" "$logfile"; then
    echo "FAIL: $label failed for an unexpected reason (expected pattern: $expected_pattern)" >&2
    cat "$logfile" >&2
    exit 1
  fi
  echo "PASS (expected rejection): $label"
}

# Bootstrap the disposable database.
psql_db < "$SQL_FILE"

# Test 1: A moves occurrence first and holds the lock; B waits, then attempts
# to create a cross-event link. A should commit; B should be rejected.
echo "Test 1/10: occurrence move obtains lock first"
reset_fixture
psql_db >"$TMP_DIR/a-first-move.log" 2>&1 <<'SQL' &
BEGIN;
SELECT s66_move_occurrence('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000002');
SELECT pg_sleep(2);
COMMIT;
SQL
a_pid=$!
sleep 0.4
expect_fail "link-after-move" "S6.6 invariant violated" docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d s66_test <<'SQL'
BEGIN;
SELECT s66_create_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
COMMIT;
SQL
wait "$a_pid"
psql_db -Atc "SELECT CASE WHEN ar.event_id <> eo.event_id AND NOT EXISTS (SELECT 1 FROM attendance_route_occurrences) THEN 'PASS' ELSE 'FAIL' END FROM attendance_routes ar CROSS JOIN event_occurrences eo WHERE ar.id='00000000-0000-0000-0000-000000000011' AND eo.id='00000000-0000-0000-0000-000000000021'" | grep -qx PASS
echo "PASS: no invalid link committed after occurrence move"

# Test 2: B creates a valid link first and holds the lock; A waits and then
# tries to move the occurrence. B should commit; A should be rejected.
echo "Test 2/10: link creation obtains lock first"
reset_fixture
psql_db >"$TMP_DIR/b-first-link.log" 2>&1 <<'SQL' &
BEGIN;
SELECT s66_create_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
SELECT pg_sleep(2);
COMMIT;
SQL
b_pid=$!
sleep 0.4
expect_fail "move-after-link" "S6.6 invariant violated" docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d s66_test <<'SQL'
BEGIN;
SELECT s66_move_occurrence('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000002');
COMMIT;
SQL
wait "$b_pid"
psql_db -Atc "SELECT CASE WHEN ar.event_id = eo.event_id AND EXISTS (SELECT 1 FROM attendance_route_occurrences) THEN 'PASS' ELSE 'FAIL' END FROM attendance_routes ar CROSS JOIN event_occurrences eo WHERE ar.id='00000000-0000-0000-0000-000000000011' AND eo.id='00000000-0000-0000-0000-000000000021'" | grep -qx PASS
echo "PASS: existing link remains consistent after rejected move"

# Test 3: multi-step move of both linked parents in one transaction is allowed.
echo "Test 3/10: consistent multi-step move commits"
reset_fixture
psql_db <<'SQL'
BEGIN;
SELECT s66_create_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
SELECT s66_move_route('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000002');
SELECT s66_move_occurrence('00000000-0000-0000-0000-000000000021', '00000000-0000-0000-0000-000000000002');
COMMIT;
SQL
psql_db -Atc "SELECT CASE WHEN ar.event_id = eo.event_id AND ar.event_id='00000000-0000-0000-0000-000000000002'::uuid THEN 'PASS' ELSE 'FAIL' END FROM attendance_routes ar CROSS JOIN event_occurrences eo WHERE ar.id='00000000-0000-0000-0000-000000000011' AND eo.id='00000000-0000-0000-0000-000000000021'" | grep -qx PASS
echo "PASS: multi-step consistent change committed"

# Test 4: direct DML without first acquiring the lock is rejected by guard.
echo "Test 4/10: direct uncoordinated write is rejected"
reset_fixture
expect_fail "direct-insert-without-lock" "requires the advisory lock" docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d s66_test <<'SQL'
INSERT INTO attendance_route_occurrences(attendance_route_id, event_occurrence_id)
VALUES ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
SQL

# Test 5: a route move races with a later link creation.
echo "Test 5/10: route move obtains lock first"
reset_fixture
psql_db >"$TMP_DIR/a-first-route-move.log" 2>&1 <<'SQL' &
BEGIN;
SELECT s66_move_route('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000002');
SELECT pg_sleep(2);
COMMIT;
SQL
a_pid=$!
sleep 0.4
expect_fail "link-after-route-move" "S6.6 invariant violated" docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d s66_test <<'SQL'
BEGIN;
SELECT s66_create_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
COMMIT;
SQL
wait "$a_pid"
psql_db -Atc "SELECT CASE WHEN ar.event_id <> eo.event_id AND NOT EXISTS (SELECT 1 FROM attendance_route_occurrences) THEN 'PASS' ELSE 'FAIL' END FROM attendance_routes ar CROSS JOIN event_occurrences eo WHERE ar.id='00000000-0000-0000-0000-000000000011' AND eo.id='00000000-0000-0000-0000-000000000021'" | grep -qx PASS
echo "PASS: no invalid link committed after route move"

# Test 6: direct parent-table event_id updates without a pre-held lock are rejected.
echo "Test 6/10: direct route and occurrence updates are rejected"
reset_fixture
expect_fail "direct-route-update-without-lock" "requires the advisory lock" docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d s66_test <<'SQL'
UPDATE attendance_routes SET event_id='00000000-0000-0000-0000-000000000002'
WHERE id='00000000-0000-0000-0000-000000000011';
SQL
expect_fail "direct-occurrence-update-without-lock" "requires the advisory lock" docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d s66_test <<'SQL'
UPDATE event_occurrences SET event_id='00000000-0000-0000-0000-000000000002'
WHERE id='00000000-0000-0000-0000-000000000021';
SQL
psql_db -Atc "SELECT CASE WHEN ar.event_id=eo.event_id AND ar.event_id='00000000-0000-0000-0000-000000000001'::uuid THEN 'PASS' ELSE 'FAIL' END FROM attendance_routes ar CROSS JOIN event_occurrences eo WHERE ar.id='00000000-0000-0000-0000-000000000011' AND eo.id='00000000-0000-0000-0000-000000000021'" | grep -qx PASS
echo "PASS: rejected direct parent updates left fixture unchanged"

# Test 7: explicit link deletion and FK cascades remove dependent links cleanly.
echo "Test 7/10: link deletion and parent/event cascades"
reset_fixture
psql_db <<'SQL'
SELECT s66_create_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
SELECT s66_delete_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
SQL
psql_db -Atc "SELECT CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM attendance_route_occurrences" | grep -qx PASS
echo "PASS: controlled link deletion removed the link"
psql_db <<'SQL'
SELECT s66_create_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
DELETE FROM attendance_routes WHERE id='00000000-0000-0000-0000-000000000011';
SQL
psql_db -Atc "SELECT CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM attendance_route_occurrences" | grep -qx PASS
echo "PASS: deleting a route cascaded to its link"
reset_fixture
psql_db <<'SQL'
SELECT s66_create_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
DELETE FROM event_occurrences WHERE id='00000000-0000-0000-0000-000000000021';
SQL
psql_db -Atc "SELECT CASE WHEN count(*)=0 THEN 'PASS' ELSE 'FAIL' END FROM attendance_route_occurrences" | grep -qx PASS
echo "PASS: deleting an occurrence cascaded to its link"
reset_fixture
psql_db <<'SQL'
SELECT s66_create_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
DELETE FROM events WHERE id='00000000-0000-0000-0000-000000000001';
SQL
psql_db -Atc "SELECT CASE WHEN (SELECT count(*) FROM attendance_route_occurrences)=0 AND (SELECT count(*) FROM attendance_routes)=0 AND (SELECT count(*) FROM event_occurrences)=0 THEN 'PASS' ELSE 'FAIL' END" | grep -qx PASS
echo "PASS: deleting the owning event cascaded through both parents and the link"

# Test 8: rollback after a successful mutation restores state and releases the transaction lock.
echo "Test 8/10: failed multi-step transaction rolls back cleanly"
reset_fixture
expect_fail "rollback-after-route-move" "occurrence not found" docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d s66_test <<'SQL'
BEGIN;
SELECT s66_move_route('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000002');
SELECT s66_move_occurrence('00000000-0000-0000-0000-000000000099', '00000000-0000-0000-0000-000000000002');
COMMIT;
SQL
psql_db -Atc "SELECT CASE WHEN event_id='00000000-0000-0000-0000-000000000001'::uuid THEN 'PASS' ELSE 'FAIL' END FROM attendance_routes WHERE id='00000000-0000-0000-0000-000000000011'" | grep -qx PASS
psql_db -c "SELECT s66_create_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021')" >/dev/null
psql_db -Atc "SELECT CASE WHEN count(*)=1 THEN 'PASS' ELSE 'FAIL' END FROM attendance_route_occurrences" | grep -qx PASS
echo "PASS: prior mutation rolled back and a subsequent transaction acquired the lock"

# Test 9: unsupported isolation is rejected.
echo "Test 9/10: unsupported isolation level is rejected"
expect_fail "repeatable-read-rejected" "supports READ COMMITTED only" docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d s66_test <<'SQL'
BEGIN ISOLATION LEVEL REPEATABLE READ;
SELECT s66_create_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
COMMIT;
SQL

# Test 10: app role cannot write tables directly but can use the granted function API.
echo "Test 10/10: application-role privilege boundary"
reset_fixture
expect_fail "app-role-direct-insert-denied" "permission denied for table attendance_route_occurrences" docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d s66_test <<'SQL'
SET ROLE s66_app;
INSERT INTO attendance_route_occurrences(attendance_route_id, event_occurrence_id)
VALUES ('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
SQL
docker exec -i "$CONTAINER" psql -X -v ON_ERROR_STOP=1 -U postgres -d s66_test <<'SQL'
BEGIN;
SET LOCAL ROLE s66_app;
SELECT public.s66_create_link('00000000-0000-0000-0000-000000000011', '00000000-0000-0000-0000-000000000021');
COMMIT;
SQL
psql_db -Atc "SELECT CASE WHEN count(*)=1 THEN 'PASS' ELSE 'FAIL' END FROM attendance_route_occurrences" | grep -qx PASS
echo "PASS: app role used the controlled function while direct table DML was denied"

echo
echo "ALL EXTENDED S6.6 PROTOTYPE TESTS PASSED"
echo "Note: disposable prototype evidence only; this is not the production schema or final S6.6 design."
