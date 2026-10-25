# Database Design 007 — Stage 6.6 — Same-Event Invariant and PostgreSQL 17 Verification

**Status:** Protocol design agreed for subsequent migration design; production SQL not authorised  
**Date recorded:** 2026-10-25  
**Depends on:** Stage 5 frozen structural design; Stage 6.4 backfill execution and verification decisions; Stage 6.5 PostgreSQL types and column definitions  
**Scope:** Consistency between attendance routes and event occurrences, transaction coordination, deferred validation, controlled writes, prototype verification and outstanding production requirements.

## 1. Decision summary

For every row in `attendance_route_occurrences`, the linked `attendance_routes.event_id` and `event_occurrences.event_id` must be equal. The invariant must hold at transaction commit, allowing a coordinated multi-step change inside one transaction but rejecting any final inconsistent state.

The selected protocol for production design is:

1. Use one deliberately global transaction-level advisory lock for all controlled writes that can affect the invariant. It is conservative and serialises these writes, favouring simplicity and correctness over concurrency.
2. Acquire the lock at the beginning of each controlled write function, before any ownership reads or data modifications.
3. Add defensive BEFORE STATEMENT triggers to reject direct INSERT/UPDATE statements on the junction table and direct changes to either parent table's `event_id` unless the transaction already holds the expected advisory lock. These triggers must not acquire a potentially late lock themselves.
4. Add initially deferred constraint triggers for junction INSERT/UPDATE and changes to either parent `event_id`. At transaction end they validate the current database state, not only the OLD/NEW row values.
5. Restrict production application roles from direct DML on the protected tables. Grant only the required controlled-function execution privileges, with a reviewed least-privilege model.
6. Initially support READ COMMITTED only through the controlled API; reject other transaction isolation levels until they are separately designed and tested.

This is a protocol-level design decision, not production SQL. The prototype's exact SQL, lock key, global validation query, test role and function grants are not production-ready copy-and-paste artefacts.

## 2. Invariant and scope

For every link row `(attendance_route_id, event_occurrence_id)`:

`attendance_routes.event_id = event_occurrences.event_id`

The invariant-affecting operations are:
- inserting or updating a link;
- changing an attendance route's `event_id`;
- changing an event occurrence's `event_id`.

Deleting a link cannot itself introduce a mismatch. Deleting a route, occurrence or owning event removes dependent link rows through the agreed cascading foreign keys. Sequential delete/cascade behaviour was exercised in the prototype; concurrency between deletes and invariant-affecting writes remains part of production review.

## 3. Transaction-coordination protocol

### 3.1 Lock acquisition

Controlled functions acquire one transaction-scoped advisory lock before doing any reads or writes relevant to the invariant. The lock is held until commit or rollback. The prototype uses a test-only key; production must choose and document a collision-resistant, application-reserved key and ensure all writers use the same protocol.

The global lock is intentionally conservative: only one transaction at a time can perform a protected write through the protocol. This avoids needing to prove a more complex per-row or per-event lock ordering. If contention later justifies a narrower scheme, it requires a separate design and concurrency proof.

### 3.2 Defensive statement-level guards

BEFORE STATEMENT triggers guard:
- INSERT or UPDATE on `attendance_route_occurrences`;
- UPDATE OF `event_id` on `attendance_routes`;
- UPDATE OF `event_id` on `event_occurrences`.

They verify that the transaction already holds the required advisory lock. They reject uncoordinated direct writes instead of trying to acquire the lock after the modifying statement has begun. This keeps lock acquisition before the statement's relevant reads/writes.

A guard is not a substitute for SQL privileges. A caller that can acquire an advisory lock still must not have direct DML permission on protected tables.

### 3.3 Deferred validation

Initially deferred constraint triggers validate the invariant for:
- junction INSERT/UPDATE;
- route `event_id` changes;
- occurrence `event_id` changes.

The check evaluates the current relationship state at deferred-trigger execution/commit. This permits a transaction to move a route and its linked occurrence together, while rejecting a transaction that leaves them associated with different events.

The prototype uses a full-table consistency query as a simple correctness oracle. Production SQL must assess this query's cost and may use targeted affected-row validation only if it preserves the same invariant under all relevant update, multi-row and cascade paths and is tested equivalently.

### 3.4 Isolation policy

The prototype's controlled functions reject transaction isolation levels other than READ COMMITTED. This is a deliberate limit, not a claim that higher isolation levels can never work. Any future support for REPEATABLE READ or SERIALIZABLE requires separate analysis and concurrency tests, including snapshot visibility after lock waits.

## 4. Controlled functions and privileges

The prototype exercises controlled functions for link creation/deletion, route movement and occurrence movement. It marks them SECURITY DEFINER and sets a fixed search_path, with underlying objects schema-qualified. An application test role has no direct table DML rights and receives EXECUTE only on the test functions.

Production must still define and review:
- the function owner and ownership of underlying tables;
- fixed search_path and schema/object qualification;
- function EXECUTE grants and PUBLIC revocations;
- table and schema privileges for every Supabase role, including service and user-facing roles;
- how RLS interacts with any SECURITY DEFINER function and whether the function intentionally bypasses caller RLS;
- validation of supplied identifiers and operation-level authorisation, not merely the invariant;
- deployment and rollback behaviour.

The test role is a simple NOLOGIN role in a disposable database. It is not a complete simulation of Supabase's anon, authenticated, service-role or RLS behaviour. Do not infer that production permissions are settled by this test.

## 5. PostgreSQL 17 prototype evidence

### Environment and scope

The extended harness was run by the project owner against a disposable Docker container using `postgres:17-alpine`. The harness creates its own temporary database container, does not publish a database port, and does not connect to the ThuScene Supabase project. The full terminal output supplied for this run ended with:

```text
ALL EXTENDED S6.6 PROTOTYPE TESTS PASSED
Note: disposable prototype evidence only; this is not the production schema or final S6.6 design.
```

### Test results

| Test group | Result | Evidence reported |
|---|---|---|
| 1. Occurrence move acquires lock first | PASS | Later inconsistent link rejected; no invalid link committed. |
| 2. Link creation acquires lock first | PASS | Later inconsistent occurrence move rejected; existing link remains consistent. |
| 3. Coordinated multi-step move | PASS | Link creation and both parent moves committed together. |
| 4. Direct link insert without lock | PASS | Defensive guard rejected the write. |
| 5. Route move acquires lock first | PASS | Later inconsistent link rejected; no invalid link committed. |
| 6. Direct parent updates | PASS | Uncoordinated route and occurrence `event_id` updates rejected; fixture unchanged. |
| 7. Delete and cascade behaviour | PASS | Controlled link deletion and route, occurrence and event cascades removed dependent links. |
| 8. Rollback and subsequent lock use | PASS | Failed multi-step transaction rolled back the earlier route change; subsequent transaction acquired the lock. |
| 9. Unsupported isolation | PASS | REPEATABLE READ use of a controlled function was rejected as designed. |
| 10. Application-role boundary | PASS | Direct link-table insert denied; controlled function succeeded for the test role. |

The harness's contention tests use separate PostgreSQL sessions: one transaction holds the advisory lock during a short sleep while another attempts the conflicting operation. The supplied output confirms the expected outcomes for those tested orderings. It does not prove correctness for every possible transaction schedule.

## 6. Evidence limits and outstanding checks

The successful run establishes that the prototype schema and tested sequences behaved as expected on PostgreSQL 17. It does not establish:

- correctness for every possible concurrency schedule;
- behaviour against the complete ThuScene schema, existing triggers, RLS or all deployed roles;
- concurrent delete/cascade interactions with link creation or parent moves;
- performance of a full-table deferred consistency scan at production scale;
- production ownership, grants, SECURITY DEFINER safety or function-level authorisation;
- migration 007/backfill correctness, deployment ordering or recovery;
- that the prototype SQL can be copied unchanged into Supabase.

Before production migration SQL is authorised, the implementation must be adapted to the actual Stage 5/6.5 schema, reviewed against Stage 6.4 backfill decisions, tested with real intended roles and relevant existing triggers, and given explicit assertions and recovery steps in S6.9. S6.7 must settle RLS, grants and public query boundaries; the privilege model in this prototype does not replace that work.

## 7. Next steps

1. Preserve the extended harness and this evidence report in the repository.
2. Complete S6.7: production role/grant/RLS/public-query boundary.
3. Complete S6.8: public pricing and display rules.
4. Complete S6.9: migration execution, backfill assertions, transaction boundaries and recovery.
5. Review the complete production migration as a whole. Only explicit later approval can authorise writing or applying it.

---

**END — Database Design 007 — Stage 6.6**
