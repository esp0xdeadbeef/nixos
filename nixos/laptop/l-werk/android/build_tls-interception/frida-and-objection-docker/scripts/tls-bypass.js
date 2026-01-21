'use strict';

Java.perform(function () {
  function cls(name) { try { return Java.use(name); } catch (_) { return null; } }

  function hook(klass, name, sig, impl) {
    try {
      const m = klass[name].overload.apply(klass[name], sig);
      m.implementation = impl;
      console.log(`[+] Hooked ${klass.$className}.${name}(${sig.join(",")})`);
      return true;
    } catch (e) { return false; }
  }

  function toJavaList(certArray) {
    const ArrayList = Java.use("java.util.ArrayList");
    const list = ArrayList.$new();
    for (let i = 0; i < certArray.length; i++) list.add(certArray[i]);
    return list;
  }

  // --------------------------------------------------------------------------
  // TrustAll TrustManager (JSSE)
  // --------------------------------------------------------------------------
  const X509TM = cls("javax.net.ssl.X509TrustManager");
  const SSLContext = cls("javax.net.ssl.SSLContext");

  let trustAllTm = null;
  if (X509TM) {
    const TrustAll = Java.registerClass({
      name: "org.deadbeef.TrustAllX509TrustManager",
      implements: [X509TM],
      methods: {
        checkClientTrusted: function () {},
        checkServerTrusted: function () {},
        getAcceptedIssuers: function () { return []; }
      }
    });
    trustAllTm = TrustAll.$new();
  }

  if (SSLContext && trustAllTm) {
    const tms = Java.array("javax.net.ssl.TrustManager", [trustAllTm]);
    hook(
      SSLContext,
      "init",
      ["[Ljavax.net.ssl.KeyManager;", "[Ljavax.net.ssl.TrustManager;", "java.security.SecureRandom"],
      function (kms, tmsIn, sr) {
        console.log("[+] SSLContext.init() -> injecting TrustAll");
        return this.init(kms, tms, sr);
      }
    );
  }

  // --------------------------------------------------------------------------
  // TrustManagerFactory.getTrustManagers() -> force our TrustAll
  // This catches cases where app builds its own SSLContext and pulls TMs from TMF.
  // --------------------------------------------------------------------------
  const TMF = cls("javax.net.ssl.TrustManagerFactory");
  if (TMF && trustAllTm) {
    hook(
      TMF,
      "getTrustManagers",
      [],
      function () {
        console.log("[+] TrustManagerFactory.getTrustManagers() -> returning TrustAll");
        return Java.array("javax.net.ssl.TrustManager", [trustAllTm]);
      }
    );
  }

  // --------------------------------------------------------------------------
  // Conscrypt TrustManagerImpl (Android platform + org.conscrypt)
  // --------------------------------------------------------------------------
  function patchTrustManagerImpl(name) {
    const TMI = cls(name);
    if (!TMI) return;

    // List-returning overload you already hit:
    hook(
      TMI,
      "checkServerTrusted",
      ["[Ljava.security.cert.X509Certificate;", "java.lang.String", "java.lang.String"],
      function (chain, authType, host) {
        console.log(`[+] ${name}.checkServerTrusted(chain,authType,host) bypass host=${host}`);
        return toJavaList(chain);
      }
    );

    // Common void-return overloads (host not always provided):
    // checkServerTrusted(chain, authType, Socket)
    hook(
      TMI,
      "checkServerTrusted",
      ["[Ljava.security.cert.X509Certificate;", "java.lang.String", "java.net.Socket"],
      function (chain, authType, socket) {
        console.log(`[+] ${name}.checkServerTrusted(chain,authType,socket) bypass`);
        return; // void
      }
    );

    // checkServerTrusted(chain, authType, SSLEngine)
    hook(
      TMI,
      "checkServerTrusted",
      ["[Ljava.security.cert.X509Certificate;", "java.lang.String", "javax.net.ssl.SSLEngine"],
      function (chain, authType, engine) {
        console.log(`[+] ${name}.checkServerTrusted(chain,authType,engine) bypass`);
        return; // void
      }
    );

    // verifyChain() variants (some devices/apps hit this instead)
    // If signature differs, hook() just fails silently.
    hook(
      TMI,
      "verifyChain",
      ["[Ljava.security.cert.X509Certificate;", "[Ljava.security.cert.X509Certificate;", "java.lang.String", "boolean", "[B", "[B"],
      function (chain, anchors, host, clientAuth, ocsp, sct) {
        console.log(`[+] ${name}.verifyChain(...) bypass host=${host}`);
        return toJavaList(chain);
      }
    );

    hook(
      TMI,
      "verifyChain",
      ["[Ljava.security.cert.X509Certificate;", "java.util.List", "java.lang.String", "boolean", "[B", "[B"],
      function (chain, anchors, host, clientAuth, ocsp, sct) {
        console.log(`[+] ${name}.verifyChain(list,...) bypass host=${host}`);
        // chain may already be a List in this overload
        return chain;
      }
    );

    console.log(`[*] Patched ${name}`);
  }

  patchTrustManagerImpl("com.android.org.conscrypt.TrustManagerImpl");
  patchTrustManagerImpl("org.conscrypt.TrustManagerImpl");

  // --------------------------------------------------------------------------
  // Hostname verification bypass (OkHttp + HttpsURLConnection)
  // --------------------------------------------------------------------------
  const OkHV = cls("okhttp3.internal.tls.OkHostnameVerifier");
  if (OkHV) {
    hook(
      OkHV,
      "verify",
      ["java.lang.String", "javax.net.ssl.SSLSession"],
      function (host, session) {
        console.log(`[+] OkHostnameVerifier.verify(session) bypass host=${host}`);
        return true;
      }
    );
    hook(
      OkHV,
      "verify",
      ["java.lang.String", "java.security.cert.X509Certificate"],
      function (host, cert) {
        console.log(`[+] OkHostnameVerifier.verify(cert) bypass host=${host}`);
        return true;
      }
    );
  }

  const HttpsURLConnection = cls("javax.net.ssl.HttpsURLConnection");
  const HostnameVerifier = cls("javax.net.ssl.HostnameVerifier");
  if (HttpsURLConnection && HostnameVerifier) {
    const AllowAllHV = Java.registerClass({
      name: "org.deadbeef.AllowAllHostnameVerifier",
      implements: [HostnameVerifier],
      methods: { verify: function (h, s) { console.log(`[+] HttpsURLConnection HV bypass host=${h}`); return true; } }
    });
    hook(
      HttpsURLConnection,
      "setDefaultHostnameVerifier",
      ["javax.net.ssl.HostnameVerifier"],
      function (hv) {
        console.log("[+] HttpsURLConnection.setDefaultHostnameVerifier() -> forcing allow-all");
        return this.setDefaultHostnameVerifier(AllowAllHV.$new());
      }
    );
    hook(
      HttpsURLConnection,
      "setHostnameVerifier",
      ["javax.net.ssl.HostnameVerifier"],
      function (hv) {
        console.log("[+] HttpsURLConnection.setHostnameVerifier() -> forcing allow-all");
        return this.setHostnameVerifier(AllowAllHV.$new());
      }
    );
  }

  // --------------------------------------------------------------------------
  // OkHttp CertificatePinner bypass (keep it)
  // --------------------------------------------------------------------------
  const CP = cls("okhttp3.CertificatePinner");
  if (CP) {
    hook(
      CP,
      "check$okhttp",
      ["java.lang.String", "kotlin.jvm.functions.Function0"],
      function (host, fn0) {
        console.log(`[+] CertificatePinner.check$okhttp bypass host=${host}`);
        return;
      }
    );
    hook(
      CP,
      "check",
      ["java.lang.String", "java.util.List"],
      function (host, list) {
        console.log(`[+] CertificatePinner.check(List) bypass host=${host}`);
        return;
      }
    );
    hook(
      CP,
      "check",
      ["java.lang.String", "[Ljava.security.cert.Certificate;"],
      function (host, certs) {
        console.log(`[+] CertificatePinner.check(Cert[]) bypass host=${host}`);
        return;
      }
    );
  }

  console.log("[*] tls-bypass-extended.js active");
});

