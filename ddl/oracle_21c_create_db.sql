-- Oracle 21c+ schema definition.
-- Run connected as the charglt user after running oracle_create_user.sql.
-- Requires Oracle 21c or later (Oracle Free 23ai also supported).
--
-- Differences from oracle_create_db.sql (19c):
--   - user_json_object uses the native JSON type instead of CLOB IS JSON
--   - user_json_cardid is a VIRTUAL generated column derived from the JSON path;
--     the stored procedures do NOT need to maintain it explicitly
--
-- For Oracle 19c use oracle_create_db.sql instead.
-- The remove script (oracle_remove_db.sql) works for both versions.

CREATE TABLE user_table (
  userid                  NUMBER(19)    NOT NULL PRIMARY KEY,
  user_last_seen          TIMESTAMP     DEFAULT SYSTIMESTAMP,
  user_softlock_sessionid NUMBER(19),
  user_softlock_expiry    TIMESTAMP,
  user_balance            NUMBER(19)    NOT NULL,
  user_json_object        JSON,
  user_json_cardid        NUMBER(19)
    GENERATED ALWAYS AS
      (TO_NUMBER(JSON_VALUE(user_json_object, '$.loyaltySchemeNumber')))
    VIRTUAL
);

CREATE INDEX ut_del          ON user_table(user_last_seen);
CREATE INDEX ut_loyaltycard  ON user_table(user_json_cardid);

CREATE TABLE user_usage_table (
  userid           NUMBER(19) NOT NULL,
  allocated_amount NUMBER(19) NOT NULL,
  sessionid        NUMBER(19) NOT NULL,
  lastdate         TIMESTAMP  NOT NULL,
  CONSTRAINT uut_pk PRIMARY KEY (userid, sessionid)
);

CREATE INDEX ust_del_idx1 ON user_usage_table(lastdate);
CREATE INDEX uut_ix1      ON user_usage_table(userid, lastdate);

CREATE TABLE user_recent_transactions (
  userid          NUMBER(19)    NOT NULL,
  user_txn_id     VARCHAR2(128) NOT NULL,
  txn_time        TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL,
  sessionid       NUMBER(19),
  approved_amount NUMBER(19),
  spent_amount    NUMBER(19),
  purpose         VARCHAR2(128),
  CONSTRAINT urt_pk PRIMARY KEY (userid, user_txn_id)
);

CREATE INDEX urt_del_idx  ON user_recent_transactions(userid, txn_time, user_txn_id);
CREATE INDEX urt_del_idx3 ON user_recent_transactions(txn_time);


CREATE OR REPLACE VIEW current_locks AS
SELECT COUNT(*) AS how_many
FROM user_table
WHERE user_softlock_expiry IS NOT NULL;

CREATE OR REPLACE VIEW allocated_credit AS
SELECT SUM(allocated_amount) AS allocated_amount
FROM user_usage_table;

CREATE OR REPLACE VIEW users_sessions AS
SELECT userid, COUNT(*) AS how_many
FROM user_usage_table
GROUP BY userid;

CREATE OR REPLACE VIEW recent_activity_out AS
SELECT TRUNC(txn_time, 'MI')    AS txn_time,
       SUM(approved_amount * -1) AS approved_amount,
       SUM(spent_amount)         AS spent_amount,
       COUNT(*)                  AS how_many
FROM user_recent_transactions
WHERE spent_amount <= 0
GROUP BY TRUNC(txn_time, 'MI');

CREATE OR REPLACE VIEW recent_activity_in AS
SELECT TRUNC(txn_time, 'MI') AS txn_time,
       SUM(approved_amount)   AS approved_amount,
       SUM(spent_amount)      AS spent_amount,
       COUNT(*)               AS how_many
FROM user_recent_transactions
WHERE spent_amount > 0
GROUP BY TRUNC(txn_time, 'MI');

CREATE OR REPLACE VIEW cluster_activity_by_users AS
SELECT userid, COUNT(*) AS how_many
FROM user_recent_transactions
GROUP BY userid;

CREATE OR REPLACE VIEW cluster_activity AS
SELECT TRUNC(txn_time, 'MI') AS txn_time, COUNT(*) AS how_many
FROM user_recent_transactions
GROUP BY TRUNC(txn_time, 'MI');

CREATE OR REPLACE VIEW last_cluster_activity AS
SELECT MAX(txn_time) AS txn_time
FROM user_recent_transactions;

CREATE OR REPLACE VIEW cluster_users AS
SELECT COUNT(*) AS how_many
FROM user_table;
