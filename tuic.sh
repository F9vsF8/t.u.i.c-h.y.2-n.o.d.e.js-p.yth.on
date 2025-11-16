#!/bin/bash 
# =========================================
# REALITY v1.4.5 over QUIC 自动部署脚本（免 root）
# 固定 SNI：www.bing.com，
# =========================================
set -euo pipefail
export LC_ALL=C
IFS=$'\n\t'

MASQ_DOMAIN="www.bing.com"
SERVER_TOML="server.toml"
CERT_PEM="reality-cert.pem"
KEY_PEM="reality-key.pem"
LINK_TXT="reality_link.txt"
REALITY_BIN="./reality-server"

# ========== 随机端口 ==========
random_port() {
  echo $(( (RANDOM % 40000) + 20000 ))
}

# ========== 选择端口 ==========
read_port() {
  if [[ $# -ge 1 && -n "${1:-}" ]]; then
    REALITY_PORT="$1"
    echo "✅ Using specified port: $REALITY_PORT"
    return
  fi

  if [[ -n "${SERVER_PORT:-}" ]]; then
    REALITY_PORT="$SERVER_PORT"
    echo "✅ Using environment port: $REALITY_PORT"
    return
  fi

  REALITY_PORT=$(random_port)
  echo "🎲 Random port selected: $REALITY_PORT"
}

# ========== 检查已有配置 ==========
load_existing_config() {
  if [[ -f "$SERVER_TOML" ]]; then
    REALITY_PORT=$(grep '^server' "$SERVER_TOML" | grep -Eo '[0-9]+')
    REALITY_ID=$(grep '^\[users\]' -A1 "$SERVER_TOML" | tail -n1 | awk '{print $1}')
    REALITY_PASSWORD=$(grep '^\[users\]' -A1 "$SERVER_TOML" | tail -n1 | awk -F'"' '{print $2}')
    echo "📂 Existing config detected. Loading..."
    return 0
  fi
  return 1
}

# ========== 生成证书 ==========
generate_cert() {
  if [[ -f "$CERT_PEM" && -f "$KEY_PEM" ]]; then
    echo "🔐 Certificate exists, skipping."
    return
  fi
  echo "🔐 Generating self-signed certificate for ${MASQ_DOMAIN}..."
  openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -keyout "$KEY_PEM" -out "$CERT_PEM" -subj "/CN=${MASQ_DOMAIN}" -days 365 -nodes >/dev/null 2>&1
  chmod 600 "$KEY_PEM"
  chmod 644 "$CERT_PEM"
}

# ========== 下载 reality-server ==========
check_reality_server() {
  if [[ -x "$REALITY_BIN" ]]; then
    echo "✅ reality-server already exists."
    return
  fi
  echo "📥 Downloading reality-server..."
  curl -L -o "$REALITY_BIN" "https://github.com/Itsusinn/reality/releases/download/v1.4.5/reality-server-x86_64-linux"
  chmod +x "$REALITY_BIN"
}

# ========== 生成配置 ==========
generate_config() {
cat > "$SERVER_TOML" <<EOF
log_level = "warn"
server = "0.0.0.0:${REALITY_PORT}"

udp_relay_ipv6 = false
zero_rtt_handshake = true
dual_stack = false
auth_timeout = "8s"
task_negotiation_timeout = "4s"
gc_interval = "8s"
gc_lifetime = "8s"
max_external_packet_size = 8192

[users]
${REALITY_ID} = "${REALITY_PASSWORD}"

[tls]
certificate = "$CERT_PEM"
private_key = "$KEY_PEM"
alpn = ["h3"]

[restful]
addr = "127.0.0.1:${REALITY_PORT}"
secret = "$(openssl rand -hex 16)"
maximum_clients_per_user = 999999999

[quic]
initial_mtu = $((1200 + RANDOM % 200))
min_mtu = 1200
gso = true
pmtu = true
send_window = 33554432
receive_window = 16777216
max_idle_time = "25s"

[quic.congestion_control]
controller = "bbr"
initial_window = 6291456
EOF
}

# ========== 获取公网IP ==========
get_server_ip() {
  curl -s --connect-timeout 3 https://api64.ipify.org || echo "127.0.0.1"
}

# ========== 生成REALITY链接 ==========
generate_link() {
  local ip="$1"
  cat > "$LINK_TXT" <<EOF
reality://${REALITY_ID}:${REALITY_PASSWORD}@${ip}:${REALITY_PORT}?alpn=h3&sni=${MASQ_DOMAIN}#REALITY-${ip}
EOF
  echo "🔗 REALITY link generated successfully:"
  cat "$LINK_TXT"
}

# ========== 守护进程 ==========
run_background_loop() {
  echo "🚀 Starting REALITY server..."
  while true; do
    "$REALITY_BIN" -c "$SERVER_TOML" >/dev/null 2>&1 || true
    echo "⚠️ REALITY crashed. Restarting in 5s..."
    sleep 5
  done
}

# ========== 主流程 ==========
main() {
  if ! load_existing_config; then
    read_port "$@"
    REALITY_ID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen)"
    REALITY_PASSWORD="$(openssl rand -hex 16)"
    generate_cert
    check_reality_server
    generate_config
  else
    generate_cert
    check_reality_server
  fi

  ip="$(get_server_ip)"
  generate_link "$ip"
  run_background_loop
}

main "$@"
