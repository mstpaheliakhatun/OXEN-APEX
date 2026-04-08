# SQL Execution Order

Run scripts in this exact order:

1. `001_schema_extensions.sql`
2. `002_seed_roles_and_mappings.sql`
3. `003_security_context_package.sql`
4. `004_row_level_security_views.sql`
5. `005_oauth_post_auth_process.sql`
6. `006_integrity_checks.sql`
7. `007_media_api.sql`

Notes:
- Execute as the schema owner containing `SUFIOUN_%` objects.
- If `sufioun_com_users.email` already exists, remove that single statement in script 001 before rerun.
- Compile invalid objects after each script:

```sql
BEGIN
  FOR r IN (
    SELECT object_name, object_type
    FROM user_objects
    WHERE status = 'INVALID'
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'ALTER ' || r.object_type || ' ' || r.object_name || ' COMPILE';
    EXCEPTION
      WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END;
/
```
