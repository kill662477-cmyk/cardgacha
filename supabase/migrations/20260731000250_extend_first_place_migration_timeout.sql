-- Keep the following first-place bulk reward migration in one atomic
-- transaction while allowing enough time for 2,167 state and mailbox rows.
-- This SET is session-scoped and disappears when the CLI connection closes.

set statement_timeout = '5min';
