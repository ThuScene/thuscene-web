# ThuScene S6.6 PostgreSQL 17 extended locking audit harness

**Disposable test only. Not a production migration. Never run this SQL against the ThuScene Supabase project.**

## Purpose

Exercise a prototype of the proposed same-event consistency protocol using an ephemeral PostgreSQL 17 Docker container:

- one deliberately global transaction-level advisory lock;
- controlled write functions that acquire the lock before modifying rows;
- defensive statement-level triggers that reject uncoordinated direct inserts/updates rather than acquiring a potentially late lock;
- deferred constraint triggers that check the final same-event invariant;
- three contention orderings (occurrence move first, link creation first, route move first);
- a valid multi-step change;
- direct-DML guards for the link table and both parent tables;
- link deletion, route/occurrence/event cascade behaviour;
- rollback after a partial transaction and subsequent lock reacquisition;
- rejection of unsupported transaction isolation; and
- an application-role check: direct table DML is denied while explicitly granted controlled functions work.

The privilege test is a prototype of one possible boundary, not a final production grant specification. The functions use SECURITY DEFINER with a fixed search_path; the test role has no direct table privileges and receives execute permission only on the controlled functions. Production needs a complete least-privilege review, including ownership, schema privileges, function execute grants, and Supabase roles/RLS policies.

## Requirements

- Docker Engine / Docker Desktop running.
- Bash, grep and standard Unix tools.
- Internet access the first time Docker needs to pull `postgres:17-alpine`.

## Run

From this directory:

```bash
chmod +x run-s6-6-postgres17-audit.sh
./run-s6-6-postgres17-audit.sh
```

The script starts a uniquely named temporary container, waits for PostgreSQL to become ready, runs the tests, and removes the container on exit. It does not publish a database port and does not connect to Supabase or any other external database.

## Test groups

1. Occurrence move holds the lock first; the later inconsistent link is rejected.
2. Link creation holds the lock first; the later inconsistent occurrence move is rejected.
3. Moving both linked parents to the same new event within one transaction succeeds.
4. Direct link-table insert without a pre-held lock is rejected.
5. Route move holds the lock first; a later inconsistent link is rejected.
6. Direct `event_id` updates to either parent table without a pre-held lock are rejected.
7. Controlled link deletion and FK cascades from route, occurrence, and event are checked.
8. A failed multi-step transaction rolls back its earlier route change; a later transaction can acquire the lock.
9. `REPEATABLE READ` use of a controlled function is rejected by this prototype's policy.
10. The application role cannot directly insert into the link table but can use the explicitly granted controlled function.

The script exits non-zero on a failed assertion or an unexpected error. A successful run ends with `ALL EXTENDED S6.6 PROTOTYPE TESTS PASSED`.

## Evidence record

The project owner supplied a successful PostgreSQL 17 run with all 10 test groups passing. The test summary and limits are recorded in [Stage 6.6 design and verification](../../Database-Design-007-Stage-6.6-Same-Event-Invariant-and-PostgreSQL-17-Verification.md).

## Important limits

- This is a small, self-contained model of the invariant, not a copy of the full ThuScene schema.
- It does not establish correctness for every possible transaction schedule, the complete production RLS/grant model, migration mechanics, all schema dependencies, or Supabase deployment behaviour.
- The full-table deferred consistency query is a prototype correctness oracle; production performance and targeted validation require review.
- The use of SECURITY DEFINER here is for the privilege test only; do not copy it into production without review of ownership, fixed search_path, schema write privileges, function execute grants, object qualification and operation-level authorisation.
- Passing this prototype does not authorise production SQL or freeze the migration implementation.
