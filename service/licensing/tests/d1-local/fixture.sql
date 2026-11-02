-- Toy persistence only. This is not the licensing/account schema.
CREATE TABLE t0_guard (id INTEGER PRIMARY KEY CHECK(id = 1), revision INTEGER NOT NULL);
CREATE TABLE t0_events (id TEXT PRIMARY KEY, detail TEXT NOT NULL);
INSERT INTO t0_guard VALUES (1, 0);
INSERT INTO t0_events VALUES ('seed', 'unchanged baseline');
