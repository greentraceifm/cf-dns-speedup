#!/bin/sh
set -eu

SIDECAR_IP="${SIDECAR_IP:-192.168.1.252}"
NFT_BIN="${NFT_BIN:-nft}"
UCI_BIN="${UCI_BIN:-uci}"
COMMENT="cfip-sidecar-direct-bypass"
CHAINS="PSW_DNS PSW_NAT PSW_MANGLE"
die() { echo "ERROR: $*" >&2; exit 1; }
validate_ip() { echo "$SIDECAR_IP" | awk -F. 'NF != 4 {exit 1} {for (i=1; i<=4; i++) if ($i !~ /^[0-9]+$/ || $i < 0 || $i > 255) exit 1}' || die "invalid SIDECAR_IP"; }
rule_exists() { "$NFT_BIN" -a list chain inet passwall "$1" 2>/dev/null | grep -F "ip saddr $SIDECAR_IP" | grep -F "comment \"$COMMENT\"" >/dev/null 2>&1; }

live_apply() {
  local chain
  validate_ip
  for chain in $CHAINS; do "$NFT_BIN" list chain inet passwall "$chain" >/dev/null 2>&1 || die "missing PassWall nft chain: $chain"; done
  for chain in $CHAINS; do rule_exists "$chain" || "$NFT_BIN" insert rule inet passwall "$chain" ip saddr "$SIDECAR_IP" counter return comment "$COMMENT"; done
}

live_remove() {
  local chain handles handle
  for chain in $CHAINS; do
    handles="$("$NFT_BIN" -a list chain inet passwall "$chain" 2>/dev/null | grep -F "ip saddr $SIDECAR_IP" | grep -F "comment \"$COMMENT\"" | sed -n 's/.* handle \([0-9][0-9]*\).*/\1/p' || true)"
    for handle in $handles; do "$NFT_BIN" delete rule inet passwall "$chain" handle "$handle"; done
  done
}

uci_install() {
  "$UCI_BIN" -q batch <<EOF
set passwall.cfip_sidecar=acl_rule
set passwall.cfip_sidecar.enabled='1'
set passwall.cfip_sidecar.remarks='CFIP Sidecar direct bypass'
set passwall.cfip_sidecar.sources='$SIDECAR_IP'
set passwall.cfip_sidecar.tcp_no_redir_ports='default'
set passwall.cfip_sidecar.udp_no_redir_ports='default'
set passwall.cfip_sidecar.tcp_proxy_drop_ports='default'
set passwall.cfip_sidecar.udp_proxy_drop_ports='default'
set passwall.cfip_sidecar.tcp_redir_ports='default'
set passwall.cfip_sidecar.udp_redir_ports='default'
set passwall.cfip_sidecar.tcp_proxy_mode='disable'
set passwall.cfip_sidecar.udp_proxy_mode='disable'
set passwall.cfip_sidecar.use_global_config='0'
set passwall.cfip_sidecar.tcp_node='default'
set passwall.cfip_sidecar.udp_node='tcp'
set passwall.cfip_sidecar.chn_list='direct'
set passwall.cfip_sidecar.dns_shunt='chinadns-ng'
set passwall.cfip_sidecar.dns_mode='dns2socks'
set passwall.cfip_sidecar.remote_dns='8.8.8.8'
EOF
  "$UCI_BIN" -q commit passwall
}
uci_remove() { "$UCI_BIN" -q delete passwall.cfip_sidecar 2>/dev/null || true; "$UCI_BIN" -q commit passwall; }

status() {
  local chain missing=0
  if [ "$("$UCI_BIN" -q get passwall.cfip_sidecar.sources 2>/dev/null || true)" = "$SIDECAR_IP" ] && [ "$("$UCI_BIN" -q get passwall.cfip_sidecar.tcp_proxy_mode 2>/dev/null || true)" = "disable" ]; then echo "uci=ok"; else echo "uci=missing_or_invalid"; missing=1; fi
  for chain in $CHAINS; do if rule_exists "$chain"; then echo "$chain=ok"; else echo "$chain=missing"; missing=1; fi; done
  return "$missing"
}

install_bypass() {
  rollback_install() {
    live_remove >/dev/null 2>&1 || true
    uci_remove >/dev/null 2>&1 || true
  }
  trap rollback_install EXIT INT TERM
  uci_install
  live_apply
  status
  trap - EXIT INT TERM
}

case "${1:-}" in
  install) install_bypass ;;
  live-apply) live_apply; status ;;
  status) status ;;
  uninstall) live_remove; uci_remove ;;
  live-remove) live_remove ;;
  *) echo "Usage: $0 {install|live-apply|status|uninstall|live-remove}" >&2; exit 2 ;;
esac
