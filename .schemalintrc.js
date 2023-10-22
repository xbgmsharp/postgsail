module.exports = {
    connection: {
      host: process.env.PGHOST,
      user: process.env.PGUSER,
      password: process.env.PGPASSWORD,
      database: process.env.PGDATABASE,
      charset: "utf8",
    },
  
    rules: {
      "name-casing": ["error", "snake"],
      "prefer-jsonb-to-json": ["error"],
      "prefer-text-to-varchar": ["error"],
      "prefer-timestamptz-to-timestamp": ["error"],
      "prefer-identity-to-serial": ["error"],
      "name-inflection": ["error", "singular"],
    },
  
    schemas: [{ name: "public" }, { name: "api" }],
  
    ignores: [],
  };