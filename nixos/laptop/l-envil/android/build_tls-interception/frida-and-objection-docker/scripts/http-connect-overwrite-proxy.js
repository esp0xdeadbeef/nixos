'use strict';

const PROXY_HOST = "10.14.0.54";
const PROXY_PORT = 8082;

function htons(p) { return ((p & 0xff) << 8) | ((p >> 8) & 0xff); }

function ip4ToBytes(ip) {
  return ip.split('.').map(x => parseInt(x, 10));
}

const ip4 = ip4ToBytes(PROXY_HOST);

const libc = Process.getModuleByName("libc.so");
const connectPtr = libc.getExportByName("connect");
console.log("[*] connect:", connectPtr);

Interceptor.attach(connectPtr, {
  onEnter(args) {
    try {
      const sa = args[1];
      if (sa == null) return;

      const family = sa.readU16();

      // IPv4
      if (family === 2) {
        const netPort = sa.add(2).readU16();
        const dport = ((netPort & 0xff) << 8) | ((netPort >> 8) & 0xff);
        if (dport === PROXY_PORT) return;

        sa.add(2).writeU16(htons(PROXY_PORT));
        sa.add(4).writeU8(ip4[0]);
        sa.add(5).writeU8(ip4[1]);
        sa.add(6).writeU8(ip4[2]);
        sa.add(7).writeU8(ip4[3]);

        return;
      }

      // IPv6
      if (family === 10) {
        const netPort = sa.add(2).readU16();
        const dport = ((netPort & 0xff) << 8) | ((netPort >> 8) & 0xff);
        if (dport === PROXY_PORT) return;

        sa.add(2).writeU16(htons(PROXY_PORT));

        // write ::ffff:10.14.0.54
        for (let i = 0; i < 10; i++) sa.add(8 + i).writeU8(0);
        sa.add(18).writeU8(0xff);
        sa.add(19).writeU8(0xff);
        sa.add(20).writeU8(ip4[0]);
        sa.add(21).writeU8(ip4[1]);
        sa.add(22).writeU8(ip4[2]);
        sa.add(23).writeU8(ip4[3]);

        return;
      }

    } catch (e) {
      console.log("[!] hook error:", e);
    }
  }
});
