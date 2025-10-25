Place environment-specific OAuth configs here.

Supported filenames (searched in this order):
- google_oauth.local.yaml    # developer machine overrides
- google_oauth.<env>.yaml    # env from --dart-define=MESSIE_ENV (dev/prod), defaults: debug→dev, release→prod

YAML schema:
issuer: https://accounts.google.com
androidClientId: YOUR_ANDROID_CLIENT_ID.apps.googleusercontent.com
iosClientId: YOUR_IOS_CLIENT_ID.apps.googleusercontent.com
redirectUri: com.your.app:/oauth2redirect
