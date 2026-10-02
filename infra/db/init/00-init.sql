-- infra/db/init/00-init.sql
--
-- Runs once, at first container start, via Postgres's
-- /docker-entrypoint-initdb.d mechanism (docker-entrypoint.sh runs every
-- *.sql/*.sh file in that directory, in lexical order, only when the data
-- directory is empty).
--
-- One Postgres instance, one database PER service (mirrors what each
-- service's %prod JDBC_URL will point at, once each service's single
-- %prod env-driven profile is wired up). All owned by the bootstrap superuser created
-- by POSTGRES_USER/POSTGRES_PASSWORD (see .env), so every service uses the
-- same credentials and only the database name differs between
-- ${JDBC_URL}s. This keeps the matrix simple (one login role) while still
-- giving each service its own schema/catalog for isolation, matching the
-- five example services that carry quarkus-jdbc-postgresql /
-- quarkus-hibernate-orm: order, inventory, notification, review, shipping.
--
-- The default POSTGRES_DB (see .env, POSTGRES_DB=appdb) is created
-- automatically by the postgres image itself before this script runs; it
-- is left as a generic/shared database for anything that doesn't need its
-- own catalog (e.g. ad hoc psql exploration).

CREATE DATABASE orderdb;
CREATE DATABASE inventorydb;
CREATE DATABASE notificationdb;
CREATE DATABASE reviewdb;
CREATE DATABASE shippingdb;
