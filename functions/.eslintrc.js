module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    "ecmaVersion": 2020,
  },
  extends: [
    "eslint:recommended",
    "google",
  ],
  rules: {
    "no-restricted-globals": ["error", "name", "length"],
    "prefer-arrow-callback": "error",
    "quotes": ["error", "double", {"allowTemplateLiterals": true}],
  },
  overrides: [
    {
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
      rules: {},
    },
    {
      files: [
        "frontDeskKiosk.js",
        "kioskRentalTermsPdf.js",
        "franchiseIdResolve.js",
      ],
      rules: {
        "require-jsdoc": "off",
        "valid-jsdoc": "off",
        "max-len": "off",
      },
    },
  ],
  globals: {},
};
