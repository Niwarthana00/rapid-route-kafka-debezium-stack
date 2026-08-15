# Kafka + Debezium CDC Stack — bus_enterprise

Streams row-level changes out of the Primary DB (`bus_enterprise_db`, Postgres 18)
into Kafka topics, ready for the Python cleaning/consumer service.

```
bus_enterprise_db (Postgres) → Debezium (Kafka Connect) → Kafka topics → Python consumer
```

## 0. One-time: enable logical replication on the Primary DB

Debezium needs `wal_level = logical` on `bus_enterprise_db`. Since that DB is
already running with data, do this with `ALTER SYSTEM` + restart rather than
rebuilding the image:

```bash
docker exec -it bus_enterprise_db psql -U postgres -d bus_enterprise -c "
  ALTER SYSTEM SET wal_level = 'logical';
  ALTER SYSTEM SET max_replication_slots = 4;
  ALTER SYSTEM SET max_wal_senders = 4;
"

# wal_level requires a full restart, not just reload
docker restart bus_enterprise_db

# verify
docker exec -it bus_enterprise_db psql -U postgres -c "SHOW wal_level;"
```

(If you'd rather bake this into the image permanently for future rebuilds,
add the same three lines to the `RUN echo ... >> postgresql.conf.sample`
block in the Primary DB's `Dockerfile`, next to the `pg_partman` settings.)

## 1. Set the real DB password in the connector config

Edit `connectors/bus-db-connector.json` and replace `REPLACE_ME` with the
actual value from `./secrets/db_password.txt` in the Primary DB project.
(Later, swap this for Connect's built-in file/vault config provider instead
of a plaintext password in the JSON — fine for now to get moving.)

## 2. Bring the stack up

```bash
docker compose up -d
```

This joins the existing `bus_enterprise_net` network (created by the Primary
DB compose file) so Kafka Connect can resolve `bus_enterprise_db` by name.
If that network doesn't exist yet, create it first: the Primary DB stack
must already be `up`.

## 3. Register the Debezium connector

```bash
chmod +x register-connector.sh
./register-connector.sh
```

## 4. Verify

- Kafka UI: http://localhost:8081 — see topics like `bus.core.drivers`,
  `bus.biz.trips`, `bus.fin.payments`, etc. (one topic per table, prefixed
  `bus.<schema>.<table>`).
- Connector status:
  ```bash
  curl -s http://localhost:8083/connectors/bus-enterprise-connector/status | python3 -m json.tool
  ```
- Make a change in `bus_enterprise_db` (e.g. `UPDATE core.drivers ...`) and
  confirm a new message shows up in the matching topic in Kafka UI within a
  couple seconds.

## Notes / knobs you'll likely want to touch later

- **`schema.include.list`** in the connector config currently includes
  `core, biz, fin, system`. Drop schemas you don't need to stream to keep
  topic count down.
- **`table.exclude.list`** excludes `system.audit_logs` as an example
  (usually noisy, rarely needed downstream) — adjust to taste.
- **Replication slot**: `debezium_bus_slot` is created automatically on
  first snapshot. If you ever tear down and rebuild the connector, drop the
  stale slot on the DB side too:
  ```sql
  SELECT pg_drop_replication_slot('debezium_bus_slot');
  ```
- **Replication factor** is set to 1 for all internal Connect topics
  (single-broker dev setup). Bump to 3 with multiple Kafka brokers for
  production durability.
- Next step once this is confirmed working: the Python consumer service
  (project 3) subscribes to these `bus.*` topics, cleans/transforms with
  pandas, and writes to the Final Analysis DB.
