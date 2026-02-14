# Postgres

List postgres extensions:
```SQL
SELECT e.extname AS "Name", e.extversion AS "Version", n.nspname AS "Schema", c.description AS "Description" 
    FROM pg_catalog.pg_extension e 
    LEFT JOIN pg_catalog.pg_namespace n ON n.oid = e.extnamespace 
    LEFT JOIN pg_catalog.pg_description c ON c.objoid = e.oid AND c.classoid = 'pg_catalog.pg_extension'::pg_catalog.regclass 
    ORDER BY 1;
```

List installed extensions available for upgrade
```SQL
SELECT name, default_version, installed_version FROM pg_available_extensions where default_version <> installed_version;
```
