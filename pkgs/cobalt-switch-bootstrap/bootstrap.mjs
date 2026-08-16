#!/usr/bin/env node
// Bootstrap the cobalt Netgear GS108PEv3 switch past its JS-driven default
// password flow, without a browser.
//
// The login page hashes the password in JavaScript (md5 of the character
// interleave of the password and the per-page `rand` token). We load the
// switch's own login.js / jquery.md5.js into a Node VM so the algorithm is
// never reimplemented here. The subsequent "Change Admin Password" step is a
// plain form POST: the CSRF token comes from pwd_ck.htm, oldPassword is the
// factory default, and newPassword is URL-encoded.
//
// The new password is read from PROSAFE_VLAN_PASSWORD and is never printed.

import { createContext, runInContext } from "node:vm";

const SWITCH = process.env.COBALT_SWITCH_ADDRESS || "192.168.1.47";
const NEW_PASSWORD = process.env.PROSAFE_VLAN_PASSWORD;
const BASE = `http://${SWITCH}`;

if (!NEW_PASSWORD) {
  console.error("PROSAFE_VLAN_PASSWORD is required");
  process.exit(1);
}

const ctx = createContext({ console });
runInContext(await (await fetch(`${BASE}/jquery.md5.js`)).text(), ctx);
runInContext(await (await fetch(`${BASE}/login.js?v1.10`)).text(), ctx);

const cookies = new Map();
const cookieHeader = () => [...cookies].map(([k, v]) => `${k}=${v}`).join("; ");
const saveCookies = (res) => {
  for (const part of res.headers.getSetCookie?.() ?? []) {
    const [pair] = part.split(";");
    const eq = pair.indexOf("=");
    if (eq >= 0) cookies.set(pair.slice(0, eq).trim(), pair.slice(eq + 1).trim());
  }
};

// 1. Log in with the factory-default password.
const loginHtml = await (await fetch(`${BASE}/login.htm`)).text();
const rand = loginHtml.match(/name="rand" value='([^']+)'/)?.[1];
if (!rand) {
  console.error("login page did not expose the rand token");
  process.exit(1);
}
const loginHash = ctx.md5(ctx.merge("password", rand));
let res = await fetch(`${BASE}/login.cgi`, {
  method: "POST",
  headers: {
    "Content-Type": "application/x-www-form-urlencoded",
    "Referer": `${BASE}/login.htm`,
  },
  body: new URLSearchParams({ password: loginHash }),
});
saveCookies(res);
if (!cookies.has("GS108SID")) {
  console.error("login did not establish a GS108SID session");
  process.exit(1);
}

// 2. Read the default-password-change CSRF token.
const pwdCk = await (
  await fetch(`${BASE}/pwd_ck.htm`, {
    headers: { "Cookie": cookieHeader(), "Referer": `${BASE}/index.htm` },
  })
).text();
const hashEle = pwdCk.match(/id=['"]hashEle['"] value=['"]([^'"]+)['"]/)?.[1];
if (!hashEle) {
  console.error("pwd_ck.htm did not expose the hashEle token");
  process.exit(1);
}

// 3. Submit the mandatory default-password change.
res = await fetch(`${BASE}/changeDefPwd.cgi`, {
  method: "POST",
  headers: {
    "Content-Type": "application/x-www-form-urlencoded",
    "Referer": `${BASE}/index.htm`,
    "Cookie": cookieHeader(),
  },
  body: new URLSearchParams({
    hash: hashEle,
    oldPassword: "password",
    newPassword: NEW_PASSWORD,
  }),
});

console.log(`switch default password changed (status ${res.status})`);
