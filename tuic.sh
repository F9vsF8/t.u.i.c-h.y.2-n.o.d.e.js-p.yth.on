#!/bin/bash
set -euo pipefail

export LC_ALL=C
IFS=$'\n\t'

TUIC_BIN="./tuic-server"
CONFIG="./config.json"
KEYS="./reality_keys.json"
LINK="./tuic_reality_link.txt"

REALITY_DOMAIN="www.cloudflare.com"
PORT=$(( (RANDOM % 20000) + 20000 ))

download_tuic() {
    if [[ -x $TUIC_BIN ]]; then
        echo "✔ TUIC 已存在"
        return
    fi
    echo "📥 下载支持 REALITY 的 TUIC"
    curl -L -o "$TUIC_BIN" \
      https://github.com/CarsonFeng/tuic/releases/latest/download/tuic-server-linux-amd64
    chmod +x "$TUIC_BIN"
}

gen_reality_keys() {
    if [[ -f "$KEYS" ]]; then
        echo "✔ REALITY 密钥已存在"
        return
    fi

    echo "🔑 生成 REALITY 私钥与公钥"
    cat > "$KEYS" <<EOF
{
  "private_key": "$(openssl genpkey -algorithm X25519 | base64)",
  "short_id": "$(openssl rand -hex 8)"
}
EOF
}

gen_config() {
    PRIVATE_KEY=$(jq -r .private_key "$KEYS")
    SHORT_ID=$(jq -r .short_id "$KEYS")
    UUID=$(cat /proc/sys/kernel/random/uuid)

cat > "$CONFIG" <<EOF
{
  "log_level": "warn",
  "inbounds": [
    {
      "type": "tuic",
      "listen": "0.0.0.0",
      "server": "::",
      "server_port": ${PORT},
      "uuid": "${UUID}",
      "password": "$(openssl rand -hex 16)",
      "congestion_control": "bbr",
      "alpn": ["h3"],
      "zero_rtt": true,
      "udp_relay_mode": "native",
      "reality": {
        "enabled": true,
        "handshake_server_name": "${REALITY_DOMAIN}",
        "private_key": "${PRIVATE_KEY}",
        "short_ids": ["${SHORT_ID}"]
      }
    }
  ]
}
EOF
}

gen_link() {
    PRIVATE_KEY=$(jq -r .private_key "$KEYS")
    SHORT_ID=$(jq -r .short_id "$KEYS")
    UUID=$(jq -r .inbounds[0].uuid "$CONFIG")
    PASSWORD=$(jq -r .inbounds[0].password "$CONFIG")
    IP=$(curl -s https://api64.ipify.org || echo "YOUR_IP")

cat > "$LINK" <<EOF
tuic://${UUID}:${PASSWORD}@${IP}:${PORT}?
allowInsecure=0&congestion_control=bbr&alpn=h3&
sni=${REALITY_DOMAIN}&disable_sni=0&
pbk=${PRIVATE_KEY}&sid=${SHORT_ID}
#TUIC-REALITY-${IP}
EOF

    echo "=========================="
    echo "✔ TUIC REALITY 节点信息生成完成："
    cat "$LINK"
    echo "=========================="
}

run_tuic() {
    echo "🚀 启动 TUIC REALITY ..."
    while true; do
        "$TUIC_BIN" -c "$CONFIG"
        echo "⚠️ TUIC 崩溃，5 秒后重启"
        sleep 5
    done
}

download_tuic
gen_reality_keys
gen_config
gen_link
run_tuic
