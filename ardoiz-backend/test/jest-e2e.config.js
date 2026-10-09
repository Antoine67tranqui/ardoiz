module.exports = {
  moduleFileExtensions: ['js', 'json', 'ts'],
  rootDir: '..',
  roots: ['<rootDir>/test', '<rootDir>/src'],
  testRegex: '.*\\.e2e-spec\\.ts$',
  transform: { '^.+\\.(t|j)s$': 'ts-jest' },
  testEnvironment: 'node',
  setupFiles: ['<rootDir>/test/setup-env.ts'],
  // Les tests partagent une vraie base Postgres : pas de parallelisme.
  maxWorkers: 1,
  testTimeout: 30000,
};
