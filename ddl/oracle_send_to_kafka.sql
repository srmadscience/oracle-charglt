-- Oracle alternative SendToKafka implementation.
-- The default stub in oracle_create_procs.sql is a no-op.
-- Replace it here if you need actual event publishing.
--
-- Option 1: Outbox table for a Kafka connector to poll (recommended)
--
--   CREATE TABLE kafka_outbox (
--     id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
--     userid      NUMBER(19)    NOT NULL,
--     txn_id      VARCHAR2(128) NOT NULL,
--     created_at  TIMESTAMP     DEFAULT SYSTIMESTAMP NOT NULL
--   );
--
--   CREATE OR REPLACE PROCEDURE SendToKafka(
--     p_userid IN NUMBER,
--     p_txnId  IN VARCHAR2
--   ) IS
--   BEGIN
--     INSERT INTO kafka_outbox (userid, txn_id) VALUES (p_userid, p_txnId);
--   END SendToKafka;
--   /
--
-- Option 2: Oracle Advanced Queuing (DBMS_AQ) — requires AQ setup first.
-- Oracle has no direct equivalent to pg_notify.

-- Default no-op stub (already created in oracle_create_procs.sql):
CREATE OR REPLACE PROCEDURE SendToKafka(
  p_userid IN NUMBER,
  p_txnId  IN VARCHAR2
) IS
BEGIN
  NULL;
END SendToKafka;
/
