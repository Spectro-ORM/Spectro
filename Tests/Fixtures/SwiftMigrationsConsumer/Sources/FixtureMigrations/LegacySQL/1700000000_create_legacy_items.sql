-- migrate:up
CREATE TABLE legacy_items (id INTEGER PRIMARY KEY, title TEXT NOT NULL);

-- migrate:down
DROP TABLE legacy_items;

