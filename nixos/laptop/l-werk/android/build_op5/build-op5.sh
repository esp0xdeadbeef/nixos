nix run path:.#inject-mitm-android-full
echo remove the proxy with:
echo "adb shell settings put global http_proxy :0"
