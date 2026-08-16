#!/usr/bin/env python3
"""Bootstrap the cobalt Netgear GS108PEv3 switch past its JS-driven default
password flow.

The GS108PEv3 web UI hashes the login password and generates the session
tokens (``hash``/``hashEle``) in JavaScript, so a plain HTTP client cannot
reproduce them. Instead we drive a headless Chromium over the DevTools
protocol: log in with the factory default, then submit the mandatory
"Change Admin Password" form, leaving the switch in the normal state so the
prosafe-vlan apply can take over.

The new password is read from PROSAFE_VLAN_PASSWORD and is never printed.
"""

import json
import os
import subprocess
import sys
import time
import urllib.request

import websocket

SWITCH = os.environ.get("COBALT_SWITCH_ADDRESS", "192.168.1.47")
DEBUG_PORT = int(os.environ.get("COBALT_SWITCH_CDP_PORT", "9333"))
NEW_PASSWORD = os.environ["PROSAFE_VLAN_PASSWORD"]


def main() -> None:
    chrome = subprocess.Popen(
        [
            "chromium",
            "--headless=new",
            "--remote-debugging-address=127.0.0.1",
            f"--remote-debugging-port={DEBUG_PORT}",
            "--remote-allow-origins=*",
            "--no-sandbox",
            "--user-data-dir=/tmp/cobalt-switch-chrome",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-session-crashed-bubble",
            "--disable-gpu",
            "--no-sandbox",
            f"http://{SWITCH}/login.htm",
        ],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )

    ws = None
    try:
        targets = None
        for _ in range(60):
            try:
                targets = json.loads(
                    urllib.request.urlopen(
                        f"http://127.0.0.1:{DEBUG_PORT}/json", timeout=2
                    ).read()
                )
                break
            except Exception:
                time.sleep(0.5)
        if targets is None:
            raise SystemExit("chromium DevTools endpoint did not come up")

        page = next(t for t in targets if t.get("type") == "page")
        ws = websocket.create_connection(page["webSocketDebuggerUrl"], timeout=20)

        msg_id = 0

        def evaluate(expression: str) -> dict:
            nonlocal msg_id
            msg_id += 1
            ws.send(
                json.dumps(
                    {
                        "id": msg_id,
                        "method": "Runtime.evaluate",
                        "params": {"expression": expression, "returnByValue": True},
                    }
                )
            )
            while True:
                message = json.loads(ws.recv())
                if message.get("id") == msg_id:
                    return message

        # Log in with the factory-default password.
        evaluate(
            "document.getElementById('password').value='password'; submitLogin();"
        )
        time.sleep(8)

        # Submit the mandatory "Change Admin Password" overlay.
        js_password = json.dumps(NEW_PASSWORD)
        evaluate(
            "document.getElementById('newPassword').value={0};"
            "document.getElementById('confirmPassword').value={0};"
            "submitChangeDefPwd();".format(js_password)
        )
        time.sleep(8)

        print("switch default password changed; prosafe-vlan can now apply")
    finally:
        if ws is not None:
            ws.close()
        chrome.terminate()


if __name__ == "__main__":
    main()
