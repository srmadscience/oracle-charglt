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

Connect as `charglt` and run:
```
sqlplus charglt/charglt@//host:1521/service @ddl/oracle_create_db.sql
```

### 3. Create the stored procedures

```
sqlplus charglt/charglt@//host:1521/service @ddl/oracle_create_procs.sql
```

### 4. Optionally replace the Kafka stub

The default `SendToKafka` procedure is a no-op. See `ddl/oracle_send_to_kafka.sql` for outbox-table and Oracle Advanced Queuing alternatives.

### 5. Build the JAR

```
mvn package -DskipTests
```

## Configuration

Connection details are set via environment variables:

| Variable | Default | Description |
|---|---|---|
| `ORA_HOST` | first CLI argument | Oracle Database hostname |
| `ORA_USER` | CLI argument | Database user |
| `ORA_PASSWORD` | CLI argument | Database password |
| `ORA_SERVICE` | `FREEPDB1` | Oracle service name (use `XE` for Express Edition, or your PDB/service name) |

Port is always **1521**. The JDBC URL format used is `jdbc:oracle:thin:@//host:1521/service`.

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

* `user_table.user_json_object` is stored as `CLOB` with an `IS JSON` constraint (Oracle 19c compatible). On Oracle 21c+ you can replace this with the native `JSON` type.
* `user_json_cardid` is a regular `NUMBER(19)` column maintained by the stored procedures. It is updated on every insert/update to `user_json_object` by extracting `$.loyaltySchemeNumber` via `JSON_VALUE`. An index on this column is created by `oracle_create_db.sql`. On Oracle 21c+ with the native `JSON` type this can instead be a virtual generated column.
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
* Oracle 21c+ path: replace `CLOB IS JSON` with native `JSON` type and use a virtual generated column for `user_json_cardid`.
