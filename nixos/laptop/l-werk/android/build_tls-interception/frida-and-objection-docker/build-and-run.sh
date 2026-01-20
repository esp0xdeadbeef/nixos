podman build -t mobile-frida-auto . 
#podman run --rm --net host -it mobile-frida-auto

podman run --rm \
  --privileged \
  --net host \
  -v ~/.android:/root/.android \
  -v ~/.adb:/root/.adb \
  -it mobile-frida-auto

#podman run --privileged --rm --net bridge -p 27042:27042 -it mobile-frida-auto

