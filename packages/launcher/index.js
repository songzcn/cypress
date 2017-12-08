// @ts-check

// compile TypeScript files on the fly using
// Node require hook project
if (process.env.CYPRESS_ENV !== 'production') {
  require('@packages/ts/register')
}
const launcher = require('./lib/launcher')
module.exports = launcher

if (!module.parent) {
  // quick way to check if TS is working
  /* eslint-disable no-console */
  console.log('Launcher project exports')
  console.log(launcher)
  console.log('⛔️ please use it as a module, not from CLI')

  launcher.printDetectedBrowsers().catch(console.error)
  /* eslint-enable no-console */
}
