module.exports = {
    connection: {
      //host: process.env.PGHOST,
      //user: process.env.PGUSER,
      //password: process.env.PGPASSWORD,
      //database: process.env.PGDATABASE,
      connectionString: process.env.PGSAIL_DB_URI,
      charset: "utf8",
    },

    rules: {
      "name-casing": ["error", "snake"],
      "prefer-jsonb-to-json": ["error"],
      "prefer-text-to-varchar": ["error"],
      "prefer-timestamptz-to-timestamp": ["error"],
      "prefer-identity-to-serial": ["error"],
      //"name-inflection": ["error", "singular"],
      'index-referencing-column': ['error'],
      'row-level-security': ['error', { enforced: true}],
      'require-primary-key': ['error', { ignorePattern: 'information_schema.*' } ],
      'index-referencing-column': ['error'],
    },

    schemas: [{ name: "public" },{ name: "api" },{ name: "auth" }],

    // (Optional) Use the `ignores` array to exclude specific targets and
    // rules. The targets are identified by the `identifier` (exact) or the
    // `identifierPattern` (regex). For the rules, use the `rule` (exact) or
    // the `rulePattern` (regex).
    ignores: [
      //{ identifier: "public.sessions", rule: "name-inflection" },
      { identifierPattern: "public\\.(aistype|app_settings|badges|geocoders|email_templates|mid|iso3166|ne_10m_geography_marine_polys)", rule: "row-level-security" },
      { identifierPattern: "public\\..*", rule: "require-primary-key" },
      { identifierPattern: "public\\.knex_migrations.*", rulePattern: ".*" },
      { identifier: "api.stays_at", rule: "row-level-security" },
      { identifier: "auth.otp", rule: "row-level-security" },
    ],
  };
