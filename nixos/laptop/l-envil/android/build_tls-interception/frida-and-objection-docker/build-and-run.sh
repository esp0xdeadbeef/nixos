podman build -t mobile-frida-auto . 
#podman run --rm --net host -it mobile-frida-auto
mkdir /home/deadbeef/.android
mkdir /home/deadbeef/.adb




# reminder how to enable the http_proxy on android:
# adb shell settings put global http_proxy "$(ip -4 a s wlp0s20f3  | grep 'inet ' | awk '{print $2}' | sed 's|/.*||g'):8082"


# waydroid notes:
# sudo mkdir -p /var/lib/waydroid/overlay/system/etc/security/cacerts/
# hash=$(openssl x509 -subject_hash_old -in ~/.mitmproxy/mitmproxy-ca-cert.pem | head -n1)
# sudo cp ~/.mitmproxy/mitmproxy-ca-cert.pem /var/lib/waydroid/overlay/system/etc/security/cacerts/$hash.0
# sudo chmod 644 /var/lib/waydroid/overlay/system/etc/security/cacerts/$hash.0
# adb shell:
# settings put global http_proxy "$(ip route show table eth0 | awk '/default/ {print $3}'):8082"

podman run --rm \
  --privileged \
  --net host \
  -v ~/.android:/root/.android \
  -v ~/.adb:/root/.adb \
  -v /mnt/current_pentest:/mnt \
  -it mobile-frida-auto

#podman run --privileged --rm --net bridge -p 27042:27042 -it mobile-frida-auto

