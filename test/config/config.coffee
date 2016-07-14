serviceAccountConfig = require './fb-service-account.json'

config =
  fbSubscriptionUID: 'podcast-hero-subscription-daemon'
  fbDatabaseConfig:
    apiKey: 'AIzaSyCfggV0QPBllvtzshhHl_vNKhlncyReuoE'
    authDomain: 'glowing-inferno-2595.firebaseapp.com'
    databaseURL: 'https://glowing-inferno-2595.firebaseio.com'
    serviceAccount: serviceAccountConfig
    databaseAuthVariableOverride: {}

module.exports = config

