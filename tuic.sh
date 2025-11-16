#!/bin/bash
set -euo pipefail
export LC_ALL=C
IFS=$'\n\t'

TUIC_BIN="./tuic-server"
CONFIG="./config.json"
KEY_FILE="./reality_private_key.b64"
SID_FILE="./reality_short_id"
LINK="./tuic_reality_link.txt"

REALITY_DOMAIN="www.cloudflare.com"
PORT=$(( (RANDOM % 20000) + 20000 ))

download_tuic() {
    if [[ -x $TUIC_BIN ]]; then
        echo "✔ TUIC 已存在"
        return
    fi
    echo "📥 下载支持 REALITY 的 TUIC（请确保该 URL 可用）"
    curl -L -o "$TUIC_BIN" \
      https://github.com/CarsonFeng/tuic/releases/latest/download/tuic-server-linux-amd64
    chmod +x "$TUIC_BIN"
}

gen_reality_keys() {
    if [[ -f "$KEY_FILE" && -f "$SID_FILE" ]]; then
        echo "✔ REALITY 密钥已存在"
        return
    fi

    echo "🔑 生成 REALITY 私钥与 short_id（并以 base64 存储私钥）"
    # 生成 X25519 私钥（PEM），然后 base64 编码保存为单行
    openssl genpkey -algorithm X25519 -out /tmp/reality_x25519.pem
    base64 -w0 /tmp/reality_x25519.pem > "$KEY_FILE"
    rm -f /tmp/reality_x25519.pem

    # short id
    openssl rand -hex 8 > "$SID_FILE"
    echo "✔ 生成完成： $KEY_FILE, $SID_FILE"
}

gen_config() {
    if [[ ! -f "$KEY_FILE" || ! -f "$SID_FILE" ]]; then
        echo "ERROR: missing keys. Run gen_reality_keys first." >&2
        exit 1
    fi

    PRIVATE_KEY_B64=$(cat "$KEY_FILE")
    SHORT_ID=$(cat "$SID_FILE")
    UUID=$(cat /proc/sys/kernel/random/uuid)
    PASSWORD=$(openssl rand -hex 16)

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
      "password": "${PASSWORD}",
      "congestion_control": "bbr",
      "alpn": ["h3"],
      "zero_rtt": true,
      "udp_relay_mode": "native",
      "reality": {
        "enabled": true,
        "handshake_server_name": "${REALITY_DOMAIN}",
        "private_key": "${PRIVATE_KEY_B64}",
        "short_ids": ["${SHORT_ID}"]
      }
    }
  ]
}
EOF

    echo "✔ config.json 已生成"
}

gen_link() {
    # 读取刚写入的 config 来获取 uuid/password（无需 jq）
    UUID=$(grep -Po '"uuid"\s*:\s*"\K[^"]+' "$CONFIG")
    PASSWORD=$(grep -Po '"password"\s*:\s*"\K[^"]+' "$CONFIG")
    PRIVATE_KEY_B64=$(cat "$KEY_FILE")
    SHORT_ID=$(cat "$SID_FILE")
    IP=$(curl -s https://api64.ipify.org || echo "YOUR_IP")

cat > "$LINK" <<EOF
tuic://${UUID}:${PASSWORD}@${IP}:${PORT}?allowInsecure=0&congestion_control=bbr&alpn=h3&sni=${REALITY_DOMAIN}&disable_sni=0&pbk=${PRIVATE_KEY_B64}&sid=${SHORT_ID}
#TUIC-REALITY-${IP}
EOF

    echo "=========================="
    echo "✔ TUIC REALITY 节点信息生成完成："
    cat "$LINK"
    echo "=========================="
}

run_tuic() {
    echo "🚀 启动 TUIC REALITY（按 Ctrl+C 停止）..."
    while true; do
        "$TUIC_BIN" -c "$CONFIG"
        echo "⚠️ TUIC 崩溃，5 秒后重启"
        sleep 5
    done
}

# 主流程
download_tuic
gen_reality_keys
gen_config
gen_link
run_tuic
