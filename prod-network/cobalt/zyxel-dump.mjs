#!/usr/bin/env node
// Read-only ZyXEL EX7501-B0 config dump / enumeration.
//
// Mirrors the Netgear switch tooling, but for the (legacy) provider-provided
// ZyXEL router: it only *reads* the router's DAL config objects and writes a
// JSON snapshot ("deviation") to prod-network/cobalt/zyxel-config-dump.json.
//
// It reuses the router's OWN javascript for the crypto instead of vendoring
// the libraries: the SPA's aes.js (CryptoJS) and jsencrypt.min.js (RSA) are
// fetched from the device and evaluated in a VM context, exactly like the web
// UI does. The login + DAL flow mirrors app.js httpReqSendAndRecv().
//
// Usage (password from sops, like the Netgear switch):
//   export ZYXEL_PASSWORD="$(sops --decrypt --extract '["password"]' secrets/s-router-cobalt-zyxel-admin-password.yaml)"
//   node prod-network/cobalt/zyxel-dump.mjs
//
// Or via the flake:  nix run .#zyxel-dump

import { createContext, runInContext } from "node:vm";
import { createHash } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

// The ZyXEL serves a self-signed cert on its LAN admin UI.
process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";

const HOST = process.env.ZYXEL_HOST ?? "https://192.168.1.1";
const PASSWORD = process.env.ZYXEL_PASSWORD ?? "";
const USERNAME = process.env.ZYXEL_USERNAME ?? "admin";
const OUT = process.env.ZYXEL_DUMP_OUT ?? "/tmp/zyxel-config-dump.json";

// The config objects worth capturing (a stable, non-secret subset).
const OIDS = [
  "wan", // WAN interfaces + the wire-VLAN -> internal-iface mapping
  "vlan_group", // 802.1Q VLAN groups
  "intf_group", // interface grouping
  "lan", // LAN/DHCP
  "lanhosts", // DHCP reservations/leases
  "user_account", // accounts (admin, group)
  "login_privilege", // per-account page allowlist + privilege
  "ethctl", // ethernet ports
  "MultiWan",
  "policy_route",
  "nat",
  "dns",
];

const objToQuery = (obj) =>
  Object.entries(obj).map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join("&");

// ---------------------------------------------------------------------------
// Minimal browser shims so the router's own JS (jsencrypt) evaluates in Node.
// ---------------------------------------------------------------------------
function makeVm() {
  const window = {
    crypto: {
      getRandomValues: (arr) => {
        // deterministic-ish fallback is fine: jsencrypt only uses this to seed
        // its RNG for RSA blinding; the entropy matters less than the padding.
        for (let i = 0; i < arr.length; i++) arr[i] = Math.floor(Math.random() * 256);
        return arr;
      },
    },
  };
  const navigator = { appName: "Netscape", appVersion: "5.0" };
  const context = createContext({ window, navigator, Math, JSON, Array, Object, Uint8Array, setTimeout, clearTimeout });
  return context;
}

async function loadJs(context, url) {
  const res = await fetch(`${HOST}${url}`, { headers: { "If-Modified-Since": "Thu, 01 Jun 1970 00:00:00 GMT" } });
  if (!res.ok) throw new Error(`GET ${url} -> ${res.status}`);
  const code = await res.text();
  runInContext(code, context, { filename: url });
}

function get(context, name) {
  return runInContext(name, context);
}

// ---------------------------------------------------------------------------
// SPA-equivalent helpers (mirrors app.js).
// ---------------------------------------------------------------------------
function aesRsaEncrypt(context, data, aesKeyB64, ivB64, rsaEncryptKey) {
  const CryptoJS = get(context, "CryptoJS");
  const iv = CryptoJS.enc.Base64.parse(ivB64);
  const key = CryptoJS.enc.Base64.parse(aesKeyB64);
  const enc = CryptoJS.AES.encrypt(data, key, { iv, mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7 });
  const out = { content: enc.toString(), key: "", iv: ivB64 };
  if (rsaEncryptKey) {
    out.key = rsaEncryptKey(aesKeyB64);
  }
  return out;
}

function aesDecrypt(context, content, aesKeyB64, ivB64) {
  const CryptoJS = get(context, "CryptoJS");
  return CryptoJS.AES.decrypt(
    content,
    CryptoJS.enc.Base64.parse(aesKeyB64),
    { iv: CryptoJS.enc.Base64.parse(ivB64), mode: CryptoJS.mode.CBC, padding: CryptoJS.pad.Pkcs7 }
  ).toString(CryptoJS.enc.Utf8);
}

function b64encode(s) {
  return Buffer.from(s, "utf8").toString("base64");
}

// ---------------------------------------------------------------------------
// HTTP (cookie + CSRF like the SPA).
// ---------------------------------------------------------------------------
let cookie = "";
let csrfToken = "";

async function req(method, url, body, extraHeaders = {}) {
  const headers = {
    "If-Modified-Since": "Thu, 01 Jun 1970 00:00:00 GMT",
    ...extraHeaders,
  };
  if (cookie) headers.Cookie = cookie;
  if (csrfToken && method !== "GET") headers.CSRFToken = csrfToken;

  const opts = { method, headers };
  if (body !== undefined) {
    headers["Content-Type"] = "application/json";
    opts.body = typeof body === "string" ? body : JSON.stringify(body);
  }

  const res = await fetch(`${HOST}${url}`, opts);
  const setCookie = res.headers.get("set-cookie");
  if (setCookie) {
    const first = setCookie.split(";")[0];
    cookie = first;
  }
  const text = await res.text();
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

// ---------------------------------------------------------------------------
// Login
// ---------------------------------------------------------------------------
async function login(context) {
  const rsa = await req("GET", "/getRSAPublickKey");
  const pub = rsa.RSAPublicKey;
  if (!pub) throw new Error("no RSAPublicKey from /getRSAPublickKey");

  // Build the RSA wrapper from the router's own jsencrypt (UMD attaches to window).
  const JSEncrypt = get(context, "window.JSEncrypt");
  const rsaEncrypt = (plainB64) => {
    const jse = new JSEncrypt();
    jse.setPublicKey(pub);
    return jse.encrypt(plainB64);
  };

  const CryptoJS = get(context, "CryptoJS");
  const iv = CryptoJS.lib.WordArray.random(32).toString(CryptoJS.enc.Base64);
  const aesKey = CryptoJS.lib.WordArray.random(32).toString(CryptoJS.enc.Base64);

  const loginData = {
    Input_Account: USERNAME,
    Input_Passwd: b64encode(PASSWORD),
    currLang: "en",
    RememberPassword: 0,
    SHA512_password: false,
  };

  const body = aesRsaEncrypt(context, JSON.stringify(loginData), aesKey, iv, rsaEncrypt);
  const resp = await req("POST", "/UserLogin", body);

  if (resp.sessionkey) {
    csrfToken = resp.sessionkey;
  } else if (resp && resp.result && resp.result !== "ZCFG_SUCCESS") {
    throw new Error(`login failed: ${JSON.stringify(resp).slice(0, 200)}`);
  }

  return { aesKey, iv };
}

// ---------------------------------------------------------------------------
// DAL dump
// ---------------------------------------------------------------------------
async function dump(context, aesKey) {
  const out = { host: HOST, dumpedAt: new Date().toISOString(), objects: {} };
  for (const oid of OIDS) {
    const url = `/cgi-bin/DAL?oid=${oid}&DalGetOneObject=y`;
    const enc = await req("GET", url);
    if (!enc || !enc.content || !enc.iv) {
      out.objects[oid] = { error: "no-encrypted-body", raw: String(enc).slice(0, 120) };
      continue;
    }
    const plain = aesDecrypt(context, enc.content, aesKey, enc.iv);
    try {
      out.objects[oid] = JSON.parse(plain);
    } catch {
      out.objects[oid] = { error: "undecryptable", plain: plain.slice(0, 200) };
    }
  }
  return out;
}

// ---------------------------------------------------------------------------
async function main() {
  if (!PASSWORD) {
    console.error("ZYXEL_PASSWORD is not set (export it from sops)");
    process.exit(1);
  }

  const context = makeVm();
  await loadJs(context, "/static/js/aes.js");
  await loadJs(context, "/static/js/jsencrypt.min.js");

  const { aesKey } = await login(context);
  const snapshot = await dump(context, aesKey);

  fs.mkdirSync(path.dirname(OUT), { recursive: true });
  fs.writeFileSync(OUT, JSON.stringify(snapshot, null, 2) + "\n");
  console.log(`wrote ${OUT}`);

  // quick summary on stdout
  const wan = snapshot.objects.wan?.Object ?? [];
  console.log("WAN interfaces:");
  for (const w of wan) {
    console.log(`  ${w.Name}: wire VLAN ${w.VLANID} -> ${w.X_ZYXEL_IfName} (${w.Encapsulation}/${w.Mode}, mtu ${w.MaxMTUSize})`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
