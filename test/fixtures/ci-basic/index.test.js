const app = require('./index')

test('says hello', () => {
  expect(app()).toBe('hello')
})
