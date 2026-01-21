
targetApp="com.redirected.store"
frida -U -f $targetApp -l ./http-connect-overwrite-proxy.js -l tls-bypass.js
