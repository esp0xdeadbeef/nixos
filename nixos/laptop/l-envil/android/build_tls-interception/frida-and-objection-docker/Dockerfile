FROM docker.io/hackermater/mobile-pentesting-setup:latest

WORKDIR /opt/frida

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        xz-utils \
        python3-venv \
        iproute2 
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        xz-utils \
        python3-venv \
        iproute2 \
        netcat-openbsd \
apktool radare2 tmux neovim
RUN rm -rf /var/lib/apt/lists/*


# Create a *fresh* venv we fully control
RUN python3 -m venv /opt/frida/venv && \
    /opt/frida/venv/bin/pip install --upgrade pip frida objection file-scraper

COPY entrypoint.sh /opt/frida/entrypoint.sh
RUN chmod +x /opt/frida/entrypoint.sh

ENTRYPOINT ["/opt/frida/entrypoint.sh"]

