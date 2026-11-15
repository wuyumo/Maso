CREATE TABLE IF NOT EXISTS partner_sandbox_attributions(
 original TEXT PRIMARY KEY,
 device TEXT NOT NULL,
 code TEXT NOT NULL REFERENCES partner_codes(code),
 created INTEGER NOT NULL,
 commission_bps INTEGER NOT NULL
);
