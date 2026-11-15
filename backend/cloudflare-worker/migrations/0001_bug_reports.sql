CREATE TABLE IF NOT EXISTS bug_reports (
  id TEXT PRIMARY KEY,
  submitted_at TEXT NOT NULL,
  body TEXT NOT NULL CHECK (length(body) <= 4000),
  app_version TEXT NOT NULL,
  os_version TEXT NOT NULL,
  language TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS bug_reports_submitted_at_idx ON bug_reports (submitted_at);
