-- Separate server-owned credit ledger. No client-supplied balance or automatic grants.
CREATE TABLE IF NOT EXISTS demo_wallets (
 id TEXT PRIMARY KEY, token_hash TEXT NOT NULL UNIQUE, balance INTEGER NOT NULL DEFAULT 0 CHECK(balance>=0),
 held INTEGER NOT NULL DEFAULT 0 CHECK(held>=0 AND held<=balance), created_at INTEGER NOT NULL
);
CREATE TABLE IF NOT EXISTS demo_jobs (
 id TEXT PRIMARY KEY, asset_key TEXT NOT NULL, exercise_id TEXT NOT NULL, recipe_json TEXT NOT NULL,
 wallet_id TEXT NOT NULL REFERENCES demo_wallets(id), cost INTEGER NOT NULL CHECK(cost>0),
 status TEXT NOT NULL CHECK(status IN ('queued','running','review','ready','failed')),
 claim_token TEXT, lease_until INTEGER, blob_key TEXT, sha256 TEXT, bytes INTEGER,
 created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, failure_code TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS demo_unique_active ON demo_jobs(asset_key) WHERE status!='failed';
CREATE INDEX IF NOT EXISTS demo_job_queue ON demo_jobs(status,created_at);
CREATE TABLE IF NOT EXISTS demo_ledger (
 id TEXT PRIMARY KEY, wallet_id TEXT NOT NULL REFERENCES demo_wallets(id), job_id TEXT,
 kind TEXT NOT NULL CHECK(kind IN ('grant','reserve','capture','release')), amount INTEGER NOT NULL, created_at INTEGER NOT NULL,
 UNIQUE(job_id,kind)
);
CREATE TABLE IF NOT EXISTS demo_assets (
 asset_key TEXT PRIMARY KEY, exercise_id TEXT NOT NULL, job_id TEXT NOT NULL UNIQUE,
 blob_key TEXT NOT NULL, sha256 TEXT NOT NULL, bytes INTEGER NOT NULL, published_at INTEGER NOT NULL
);
CREATE TRIGGER IF NOT EXISTS demo_reserve AFTER INSERT ON demo_jobs BEGIN
 SELECT CASE WHEN NOT EXISTS(SELECT 1 FROM demo_wallets WHERE id=NEW.wallet_id AND balance-held>=NEW.cost)
 THEN RAISE(ABORT,'insufficient_credits') END;
 UPDATE demo_wallets SET held=held+NEW.cost WHERE id=NEW.wallet_id;
 INSERT INTO demo_ledger VALUES(NEW.id||':reserve',NEW.wallet_id,NEW.id,'reserve',NEW.cost,NEW.created_at);
END;
CREATE TRIGGER IF NOT EXISTS demo_capture AFTER UPDATE OF status ON demo_jobs
WHEN NEW.status='ready' AND OLD.status='review' BEGIN
 UPDATE demo_wallets SET balance=balance-NEW.cost,held=held-NEW.cost WHERE id=NEW.wallet_id;
 INSERT INTO demo_ledger VALUES(NEW.id||':capture',NEW.wallet_id,NEW.id,'capture',NEW.cost,NEW.updated_at);
 INSERT INTO demo_assets VALUES(NEW.asset_key,NEW.exercise_id,NEW.id,NEW.blob_key,NEW.sha256,NEW.bytes,NEW.updated_at);
END;
CREATE TRIGGER IF NOT EXISTS demo_release AFTER UPDATE OF status ON demo_jobs
WHEN NEW.status='failed' AND OLD.status NOT IN ('failed','ready') BEGIN
 UPDATE demo_wallets SET held=held-NEW.cost WHERE id=NEW.wallet_id;
 INSERT INTO demo_ledger VALUES(NEW.id||':release',NEW.wallet_id,NEW.id,'release',NEW.cost,NEW.updated_at);
END;
