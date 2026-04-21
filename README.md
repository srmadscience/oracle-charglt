# oracle-charglt
Oracle Database implementation of [Charglt](https://github.com/srmadscience/voltdb-charglt)

It has the same basic functionality as charglt, adapted for Oracle Database — see TODO for known gaps.

Far more documentation about the benchmark itself is available at the link above.

## See Also:

* [postgres-charglt](https://github.com/srmadscience/postgres-charglt)
* [mongodb-charglt](https://github.com/srmadscience/mongodb-charglt)
* [redis-charglt](https://github.com/srmadscience/redis-charglt)
* [voltdb-charglt](https://github.com/srmadscience/voltdb-charglt)

## Prerequisites

* Oracle Database 19c or later (Oracle Free 23ai or XE also supported)
* Java 21
* Maven

## Installation

### 1. Create the schema

Connect as SYSDBA (or a DBA-privileged account) and run:
```
sqlplus sys/password@//host:1521/service as sysdba @ddl/oracle_create_user.sql
```

This creates the `charglt` user/schema with the necessary privileges. The default password is `charglt` — change it in the file before running in any non-development environment.

### 2. Create the tables and views

Choose the DDL set that matches your Oracle version (see [Schema version](#schema-version)):

**Oracle 19c (default):**
```
sqlplus charglt/charglt@//host:1521/service @ddl/oracle_create_db.sql
```

**Oracle 21c+:**
```
sqlplus charglt/charglt@//host:1521/service @ddl/oracle_21c_create_db.sql
```

### 3. Create the stored procedures

**Oracle 19c (default):**
```
sqlplus charglt/charglt@//host:1521/service @ddl/oracle_create_procs.sql
```

**Oracle 21c+:**
```
sqlplus charglt/charglt@//host:1521/service @ddl/oracle_21c_create_procs.sql
```

### 4. Optionally replace the Kafka stub

The default `SendToKafka` procedure is a no-op. See `ddl/oracle_send_to_kafka.sql` for outbox-table and Oracle Advanced Queuing alternatives.

### 5. Build the JAR

```
mvn package -DskipTests
```

## Configuration

Connection details and schema version are set via environment variables:

| Variable | Default | Description |
|---|---|---|
| `ORA_HOST` | first CLI argument | Oracle Database hostname |
| `ORA_USER` | CLI argument | Database user |
| `ORA_PASSWORD` | CLI argument | Database password |
| `ORA_SERVICE` | `FREEPDB1` | Oracle service name (use `XE` for Express Edition, or your PDB/service name) |
| `ORA_VERSION` | `19` | Schema version mode: `19` for Oracle 19c+, `21` for Oracle 21c+ |

Port is always **1521**. The JDBC URL format used is `jdbc:oracle:thin:@//host:1521/service`.

## Schema version

Two DDL paths are provided. The stored procedure interface is identical in both — no Java code changes are needed when switching versions.

| `ORA_VERSION` | DDL files | `user_json_object` type | `user_json_cardid` |
|---|---|---|---|
| `19` (default) | `oracle_create_db.sql` + `oracle_create_procs.sql` | `CLOB IS JSON` | Regular column, maintained by stored procedures |
| `21` | `oracle_21c_create_db.sql` + `oracle_21c_create_procs.sql` | Native `JSON` type | Virtual generated column (automatic) |

The `oracle_remove_db.sql` cleanup script works for both versions.

## Running the benchmark

### Load data — CreateChargingDemoData

```
hostname usercount tpms maxinitialcredit username password
```

Example — load 100,000 users at up to 10 transactions per millisecond, each starting with up to 1,000 units of credit:
```
10.13.1.101 100000 10 1000 charglt charglt
```

### Transaction benchmark — ChargingDemoTransactions

```
hostname usercount tpms durationseconds queryseconds username password workercount
```

Example — run against 100,000 users at 10 tpms for 120 seconds, printing global stats every 30 seconds, using a single thread:
```
10.13.1.101 100000 10 120 30 charglt charglt 0
```

### Key-Value store benchmark — ChargingDemoKVStore

```
hostname usercount tpms durationseconds queryseconds jsonsize deltaproportion username password workercount
```

Example — 100 users, 1 tpms, 60 seconds, stats every 15 seconds, 100-byte JSON payloads, 50% delta updates:
```
10.13.1.101 100 1 60 15 100 50 charglt charglt 0
```

### Delete data — DeleteChargingDemoData

```
hostname usercount tpms username password
```

## Schema notes

* `user_table.user_json_object` is stored as `CLOB IS JSON` (19c) or native `JSON` type (21c+), selected by the DDL path used at install time.
* `user_json_cardid` is a regular `NUMBER(19)` column in 19c mode, updated by stored procedures on every write. In 21c+ mode it is a virtual generated column computed automatically from `$.loyaltySchemeNumber`. Both modes create an index on this column.
* All stored procedures are Oracle PL/SQL. Status-returning procedures use `OUT NUMBER` / `OUT VARCHAR2` parameters. Multi-row procedures (`GetUser`, `GetUsersWithMultipleSessions`, `showTransactions`) return a `SYS_REFCURSOR`. Java calls all procedures via `CallableStatement`.
* Kafka integration is stubbed as a no-op `SendToKafka` procedure. Oracle has no equivalent to `pg_notify`; see `ddl/oracle_send_to_kafka.sql` for alternatives using an outbox table or Oracle Advanced Queuing (DBMS_AQ).

## Removing the schema

```
sqlplus charglt/charglt@//host:1521/service @ddl/oracle_remove_db.sql
```

To also drop the user/schema entirely (run as SYSDBA):
```sql
DROP USER charglt CASCADE;
```

## TODO

* Implement `ShowCurrentAllocations` (running totals), present in the VoltDB original.
* Scaled multi-worker tests have not yet been validated end-to-end.
