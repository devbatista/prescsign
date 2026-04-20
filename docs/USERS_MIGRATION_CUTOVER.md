# Users Migration Cutover Runbook

## Goal

Move to user-only authentication with no automatic fallback provisioning from legacy `doctors`.

## Final Flags

Set these values in the target environment:

- `USERS_MIGRATION_PHASE=phase3_users_required`
- `AUTH_USERS_REQUIRED=true`
- `AUTH_USERS_FALLBACK_PROVISIONING=false`
- `USERS_MIGRATION_ALLOW_DOCTOR_FALLBACK=false`
- `OBS_ROLLOUT_PHASE=users_migration_cutover`

## Readiness Checklist

1. Run backfill consistency gate:
   - `bundle exec rake users:migration:readiness`
2. Run migration critical regression suite:
   - `bundle exec rake qa:users_migration_regression`
3. Confirm there are no pending inconsistencies in the readiness output:
   - `missing_mapping_doctor_ids`
   - `missing_doctor_profile_doctor_ids`
   - `pending_internal_responsible_ids`

## Post-Cutover Monitoring

Monitor application logs for these events:

- `users_migration_fallback_provisioned`
  - Expected after cutover: zero occurrences.
- `users_migration_users_required_block`
  - Any occurrence indicates identity gaps that must be remediated.
- `http_endpoint_monitor`
  - Watch for spikes in `status_http` 401/403/500.

## Rollback

If user-only cutover causes elevated auth errors:

1. Re-enable transitional mode:
   - `AUTH_USERS_REQUIRED=false`
   - `AUTH_USERS_FALLBACK_PROVISIONING=true`
   - `USERS_MIGRATION_ALLOW_DOCTOR_FALLBACK=true`
   - `USERS_MIGRATION_PHASE=phase2_users_auth_enabled`
2. Keep observability phase explicit for incident tracking:
   - `OBS_ROLLOUT_PHASE=users_migration_rollback`
3. Run:
   - `bundle exec rake users:backfill:from_doctors`
   - `bundle exec rake users:migration:readiness`
4. Re-run:
   - `bundle exec rake qa:users_migration_regression`

## Exit Criteria

- Readiness check passing.
- Regression suite passing.
- Zero `users_migration_fallback_provisioned` events in agreed stabilization window.
- No abnormal rise in auth/resource 401/403/500 rates.
