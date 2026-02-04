
This is how I've setup the emulator:
```
# optional:
avdmanager delete avd -n pixel9pro-test 2>/dev/null || true
avdmanager create avd \
  -n pixel9pro-test \
  -k "system-images;android-34;google_apis;x86_64" \
  -d "pixel_9_pro"
emulator -avd pixel9pro-test -gpu swiftshader_indirect -no-snapshot -verbose
```
