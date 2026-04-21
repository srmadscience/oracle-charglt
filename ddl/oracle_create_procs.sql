-- Oracle PL/SQL stored procedures.
-- Run connected as the charglt user after running oracle_create_db.sql.
-- Each block must be terminated with '/' on a line by itself.
--
-- Key differences from PostgreSQL PL/pgSQL:
--   - RETURNS TABLE(...)    -> OUT SYS_REFCURSOR (for multi-row) or OUT NUMBER/VARCHAR2 (for status)
--   - CLOCK_TIMESTAMP()     -> SYSTIMESTAMP
--   - INTERVAL '1 second'   -> INTERVAL '1' SECOND
--   - jsonb_set(...)        -> JSON_MERGEPATCH(...)
--   - SELECT INTO raises NO_DATA_FOUND on 0 rows (must be caught)
--   - PERFORM func(...)     -> func(...);
--   - p_json::JSONB         -> p_json  (VARCHAR2 auto-coerced to CLOB)
--   - user_json_cardid is a regular column; must be updated explicitly


CREATE OR REPLACE PROCEDURE SendToKafka(
  p_userid IN NUMBER,
  p_txnId  IN VARCHAR2
) IS
BEGIN
  NULL;
END SendToKafka;
/


CREATE OR REPLACE PROCEDURE DelUser(p_userid IN NUMBER) IS
BEGIN
  DELETE FROM user_recent_transactions WHERE userid = p_userid;
  DELETE FROM user_usage_table         WHERE userid = p_userid;
  DELETE FROM user_table               WHERE userid = p_userid;
END DelUser;
/


CREATE OR REPLACE PROCEDURE GetAndLockUser(
  p_userid        IN  NUMBER,
  p_new_lock_id   IN  NUMBER,
  p_status_byte   OUT NUMBER,
  p_status_string OUT VARCHAR2
) IS
  l_found_userid            NUMBER(19);
  l_user_softlock_expiry    TIMESTAMP;
  l_user_softlock_sessionid NUMBER(19);
BEGIN
  BEGIN
    SELECT userid, user_softlock_expiry, user_softlock_sessionid
    INTO l_found_userid, l_user_softlock_expiry, l_user_softlock_sessionid
    FROM user_table
    WHERE userid = p_userid;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      p_status_byte   := 50;
      p_status_string := 'User ' || p_userid || ' does not exist';
      RETURN;
  END;

  IF l_user_softlock_sessionid = p_new_lock_id
     OR l_user_softlock_expiry IS NULL
     OR l_user_softlock_expiry < SYSTIMESTAMP
  THEN
    UPDATE user_table
    SET user_softlock_sessionid = p_new_lock_id,
        user_softlock_expiry    = SYSTIMESTAMP + INTERVAL '1' SECOND
    WHERE userid = p_userid;
    p_status_byte   := 54;
    p_status_string := 'User ' || p_userid || ' locked by session ' || l_user_softlock_sessionid;
  ELSE
    p_status_byte   := 53;
    p_status_string := 'User ' || p_userid || ' already locked by session ' || l_user_softlock_sessionid;
  END IF;
END GetAndLockUser;
/


CREATE OR REPLACE PROCEDURE UpdateLockedUser(
  p_userid               IN  NUMBER,
  p_new_lock_id          IN  NUMBER,
  p_json_payload         IN  VARCHAR2,
  p_delta_operation_name IN  VARCHAR2,
  p_status_byte          OUT NUMBER,
  p_status_string        OUT VARCHAR2
) IS
  l_found_userid            NUMBER(19);
  l_user_softlock_expiry    TIMESTAMP;
  l_user_softlock_sessionid NUMBER(19);
BEGIN
  BEGIN
    SELECT userid, user_softlock_expiry, user_softlock_sessionid
    INTO l_found_userid, l_user_softlock_expiry, l_user_softlock_sessionid
    FROM user_table
    WHERE userid = p_userid;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN
      p_status_byte   := 50;
      p_status_string := 'User ' || p_userid || ' does not exist';
      RETURN;
  END;

  IF l_user_softlock_sessionid = p_new_lock_id
     OR l_user_softlock_expiry IS NULL
     OR l_user_softlock_expiry < SYSTIMESTAMP
  THEN
    IF p_delta_operation_name = 'NEW_LOYALTY_NUMBER' THEN
      UPDATE user_table
      SET user_softlock_sessionid = NULL,
          user_softlock_expiry    = NULL,
          user_json_object        = JSON_MERGEPATCH(NVL(user_json_object, '{}'),
                                      '{"loyaltySchemeNumber":' || TO_NUMBER(p_json_payload) || '}'),
          user_json_cardid        = TO_NUMBER(p_json_payload)
      WHERE userid = p_userid;
    ELSE
      UPDATE user_table
      SET user_softlock_sessionid = NULL,
          user_softlock_expiry    = NULL,
          user_json_object        = p_json_payload,
          user_json_cardid        = TO_NUMBER(JSON_VALUE(p_json_payload, '$.loyaltySchemeNumber'))
      WHERE userid = p_userid;
    END IF;
    p_status_byte   := 42;
    p_status_string := 'User ' || p_userid || ' updated';
  ELSE
    p_status_byte   := 53;
    p_status_string := 'User ' || p_userid || ' already locked by session ' || l_user_softlock_sessionid;
  END IF;
END UpdateLockedUser;
/


CREATE OR REPLACE PROCEDURE UpsertUser(
  p_userid        IN  NUMBER,
  p_addBalance    IN  NUMBER,
  p_json          IN  VARCHAR2,
  p_purpose       IN  VARCHAR2,
  p_lastSeen      IN  TIMESTAMP,
  p_txnId         IN  VARCHAR2,
  p_status_byte   OUT NUMBER,
  p_status_string OUT VARCHAR2
) IS
  l_found_userid  NUMBER(19);
  l_found_txn_id  VARCHAR2(128);
BEGIN
  BEGIN
    SELECT userid INTO l_found_userid FROM user_table WHERE userid = p_userid;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_found_userid := NULL;
  END;

  BEGIN
    SELECT user_txn_id INTO l_found_txn_id
    FROM user_recent_transactions
    WHERE userid = p_userid AND user_txn_id = p_txnId;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_found_txn_id := NULL;
  END;

  IF l_found_txn_id IS NOT NULL AND l_found_txn_id = p_txnId THEN
    p_status_byte   := 46;
    p_status_string := 'Txn ' || p_txnId || ' already happened';
  ELSE
    IF l_found_userid IS NOT NULL THEN
      UPDATE user_table
      SET user_json_object        = p_json,
          user_json_cardid        = TO_NUMBER(JSON_VALUE(p_json, '$.loyaltySchemeNumber')),
          user_last_seen          = p_lastSeen,
          user_balance            = p_addBalance,
          user_softlock_expiry    = NULL,
          user_softlock_sessionid = NULL
      WHERE userid = p_userid;
      p_status_string := 'User ' || p_userid || ' updated';
    ELSE
      INSERT INTO user_table (userid, user_json_object, user_json_cardid, user_last_seen, user_balance)
      VALUES (p_userid, p_json,
              TO_NUMBER(JSON_VALUE(p_json, '$.loyaltySchemeNumber')),
              p_lastSeen, p_addBalance);
      p_status_string := 'User ' || p_userid || ' inserted';
    END IF;
    p_status_byte := 42;
    INSERT INTO user_recent_transactions
      (userid, user_txn_id, txn_time, approved_amount, spent_amount, purpose)
    VALUES (p_userid, p_txnId, p_lastSeen, 0, p_addBalance, 'Create User');
    SendToKafka(p_userid, p_txnId);
  END IF;
END UpsertUser;
/


CREATE OR REPLACE PROCEDURE AddCredit(
  p_userid        IN  NUMBER,
  p_extra_credit  IN  NUMBER,
  p_txnId         IN  VARCHAR2,
  p_status_byte   OUT NUMBER,
  p_status_string OUT VARCHAR2
) IS
  l_found_userid NUMBER(19);
  l_found_txn_id VARCHAR2(128);
BEGIN
  BEGIN
    SELECT userid INTO l_found_userid FROM user_table WHERE userid = p_userid;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_found_userid := NULL;
  END;

  BEGIN
    SELECT user_txn_id INTO l_found_txn_id
    FROM user_recent_transactions
    WHERE userid = p_userid AND user_txn_id = p_txnId;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_found_txn_id := NULL;
  END;

  IF l_found_txn_id = p_txnId THEN
    p_status_byte   := 46;
    p_status_string := 'Txn ' || p_txnId || ' already happened';
  ELSE
    IF l_found_userid IS NOT NULL THEN
      UPDATE user_table
      SET user_balance = user_balance + p_extra_credit
      WHERE userid = p_userid;

      INSERT INTO user_recent_transactions
        (userid, user_txn_id, txn_time, approved_amount, spent_amount, purpose)
      VALUES (p_userid, p_txnId, SYSTIMESTAMP, 0, p_extra_credit, 'Add Credit');

      SendToKafka(p_userid, p_txnId);

      DELETE FROM user_recent_transactions
      WHERE userid = p_userid
        AND txn_time < SYSTIMESTAMP - INTERVAL '1' SECOND;

      p_status_byte   := 56;
      p_status_string := p_extra_credit || ' added by Txn ' || p_txnId;
    ELSE
      p_status_byte   := 50;
      p_status_string := 'User ' || p_userid || ' does not exist';
    END IF;
  END IF;
END AddCredit;
/


CREATE OR REPLACE PROCEDURE ReportQuotaUsage(
  p_userid        IN  NUMBER,
  p_units_used    IN  NUMBER,
  p_units_wanted  IN  NUMBER,
  p_sessionid     IN  NUMBER,
  p_txnId         IN  VARCHAR2,
  p_status_byte   OUT NUMBER,
  p_status_string OUT VARCHAR2
) IS
  l_found_userid     NUMBER(19);
  l_found_txn_id     VARCHAR2(128);
  l_balance          NUMBER(19) := 0;
  l_allocated_amount NUMBER(19) := 0;
  l_amount_spent     NUMBER(19);
  l_available_credit NUMBER(19) := 0;
  l_offered_credit   NUMBER(19) := 0;
BEGIN
  l_amount_spent := p_units_used * -1;

  BEGIN
    SELECT userid, user_balance
    INTO l_found_userid, l_balance
    FROM user_table
    WHERE userid = p_userid;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_found_userid := NULL;
  END;

  BEGIN
    SELECT user_txn_id INTO l_found_txn_id
    FROM user_recent_transactions
    WHERE userid = p_userid AND user_txn_id = p_txnId;
  EXCEPTION
    WHEN NO_DATA_FOUND THEN l_found_txn_id := NULL;
  END;

  SELECT NVL(SUM(allocated_amount), 0)
  INTO l_allocated_amount
  FROM user_usage_table
  WHERE userid = p_userid AND sessionid != p_sessionid;

  IF l_found_txn_id = p_txnId THEN
    p_status_byte   := 46;
    p_status_string := 'Txn ' || p_txnId || ' already happened';
  ELSE
    IF l_found_userid IS NOT NULL THEN
      DELETE FROM user_usage_table WHERE userid = p_userid AND sessionid = p_sessionid;

      l_available_credit := l_balance + l_amount_spent - l_allocated_amount;

      IF l_available_credit < 0 THEN
        p_status_byte   := 43;
        p_status_string := 'Negative balance: ' || l_available_credit;
      ELSE
        IF p_units_wanted > l_available_credit THEN
          l_offered_credit := l_available_credit;
          p_status_byte    := 44;
          p_status_string  := l_offered_credit || ' of ' || p_units_wanted || ' Allocated';
        ELSE
          l_offered_credit := p_units_wanted;
          p_status_byte    := 45;
          p_status_string  := l_offered_credit || ' Allocated';
        END IF;

        INSERT INTO user_recent_transactions
          (userid, user_txn_id, txn_time, approved_amount, spent_amount, purpose)
        VALUES (p_userid, p_txnId, SYSTIMESTAMP, l_offered_credit, l_amount_spent, 'Spend');

        SendToKafka(p_userid, p_txnId);
      END IF;

      UPDATE user_table
      SET user_balance = user_balance + l_amount_spent
      WHERE userid = p_userid;

      IF l_offered_credit > 0 THEN
        INSERT INTO user_usage_table (userid, allocated_amount, sessionid, lastdate)
        VALUES (p_userid, l_offered_credit, p_sessionid, SYSTIMESTAMP);
      END IF;

      DELETE FROM user_recent_transactions
      WHERE userid = p_userid
        AND txn_time < SYSTIMESTAMP - INTERVAL '1' SECOND;
    ELSE
      p_status_byte   := 50;
      p_status_string := 'User ' || p_userid || ' does not exist';
    END IF;
  END IF;
END ReportQuotaUsage;
/


CREATE OR REPLACE PROCEDURE GetUser(
  p_userid IN  NUMBER,
  p_cursor OUT SYS_REFCURSOR
) IS
BEGIN
  OPEN p_cursor FOR
    SELECT userid FROM user_table            WHERE userid = p_userid
    UNION ALL
    SELECT userid FROM user_usage_table      WHERE userid = p_userid
    UNION ALL
    SELECT userid FROM user_recent_transactions WHERE userid = p_userid;
END GetUser;
/


CREATE OR REPLACE PROCEDURE GetUsersWithMultipleSessions(
  p_cursor OUT SYS_REFCURSOR
) IS
BEGIN
  OPEN p_cursor FOR
    SELECT userid, how_many
    FROM users_sessions
    WHERE how_many > 1
    ORDER BY how_many, userid
    FETCH FIRST 50 ROWS ONLY;
END GetUsersWithMultipleSessions;
/


CREATE OR REPLACE PROCEDURE showTransactions(
  p_userid IN  NUMBER,
  p_cursor OUT SYS_REFCURSOR
) IS
BEGIN
  OPEN p_cursor FOR
    SELECT userid, user_txn_id, txn_time, sessionid,
           approved_amount, spent_amount, purpose
    FROM user_recent_transactions
    WHERE userid = p_userid
    ORDER BY txn_time, user_txn_id;
END showTransactions;
/
