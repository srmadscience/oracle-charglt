-- Oracle schema/user creation.
-- Run as SYSDBA or a DBA-privileged account.
-- In Oracle, creating a user IS creating a schema.

CREATE USER charglt IDENTIFIED BY charglt
  DEFAULT TABLESPACE users
  TEMPORARY TABLESPACE temp
  QUOTA UNLIMITED ON users;

GRANT CONNECT, RESOURCE, CREATE VIEW TO charglt;
