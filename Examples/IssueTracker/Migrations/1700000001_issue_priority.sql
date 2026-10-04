-- migrate:up
ALTER TABLE issues ADD COLUMN priority INT NOT NULL DEFAULT 0;
UPDATE issues SET priority = 1 WHERE display_name LIKE 'First%';
CREATE INDEX issues_project_id_idx ON issues(project_id);

-- migrate:down
DROP INDEX issues_project_id_idx;
ALTER TABLE issues DROP COLUMN priority;
