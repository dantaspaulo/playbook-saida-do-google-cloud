#!/usr/bin/env bash
# Fecha 80 e 443 da VPS para tudo que não seja a Cloudflare.
#
# Por quê: com a origem aberta, qualquer um fala direto com o servidor, pula o
# WAF e forja o cabeçalho de IP do visitante (todo limite por IP vira enfeite).
#
# A regra vai na cadeia DOCKER-USER: o Docker publica portas por fora do UFW, e
# o filtro precisa olhar a porta ORIGINAL (antes do NAT), por isso o conntrack.
#
# Uso:
#   sudo bash origem-cloudflare.sh              mostra o que faria (não muda nada)
#   sudo bash origem-cloudflare.sh --aplicar    aplica
#   sudo bash origem-cloudflare.sh --remover    desfaz
# Para valer depois do reboot, rode com --aplicar num serviço do systemd que
# começa depois do docker.service (After=docker.service).
#
# Antes de aplicar, MEÇA: um `tcpdump -nn 'tcp[tcpflags] & tcp-syn != 0 and (port 80 or 443)'`
# por algumas horas mostra quem chega direto e o que vai parar de funcionar.
set -euo pipefail

MODO="${1:-mostrar}"
IFACE="${IFACE:-$(ip route get 1.1.1.1 | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')}"
CADEIA=CF-ORIGEM

faixas() {
  # A lista vem SEM quebra de linha no fim: o `echo` garante que a última faixa não se perca.
  { curl -fsS "https://www.cloudflare.com/ips-$1"; echo; } | sed '/^[[:space:]]*$/d'
}

aplicar_familia() {
  local ipt="$1" fam="$2" lista n
  lista="$(faixas "$fam")"
  n="$(printf '%s\n' "$lista" | wc -l | tr -d ' ')"
  if [ "$n" -lt 5 ]; then
    echo "lista $fam da Cloudflare veio estranha ($n faixas); parando sem mexer" >&2
    exit 1
  fi
  echo "== $ipt: $n faixas da Cloudflare, interface $IFACE"
  local cmds=()
  cmds+=("$ipt -N $CADEIA 2>/dev/null || $ipt -F $CADEIA")
  while IFS= read -r f; do
    cmds+=("$ipt -A $CADEIA -s $f -j RETURN")
  done <<< "$lista"
  cmds+=("$ipt -A $CADEIA -j DROP")
  for porta in 80 443; do
    cmds+=("$ipt -C DOCKER-USER -i $IFACE -p tcp -m conntrack --ctorigdstport $porta --ctdir ORIGINAL -j $CADEIA 2>/dev/null || $ipt -I DOCKER-USER -i $IFACE -p tcp -m conntrack --ctorigdstport $porta --ctdir ORIGINAL -j $CADEIA")
  done
  for c in "${cmds[@]}"; do
    if [ "$MODO" = "--aplicar" ]; then bash -c "$c"; else echo "  $c"; fi
  done
}

remover_familia() {
  local ipt="$1"
  for porta in 80 443; do
    while $ipt -D DOCKER-USER -i "$IFACE" -p tcp -m conntrack --ctorigdstport "$porta" --ctdir ORIGINAL -j "$CADEIA" 2>/dev/null; do :; done
  done
  $ipt -F "$CADEIA" 2>/dev/null || true
  $ipt -X "$CADEIA" 2>/dev/null || true
  echo "== $ipt: regras removidas"
}

case "$MODO" in
  --remover)
    remover_familia iptables
    command -v ip6tables >/dev/null && remover_familia ip6tables
    ;;
  --aplicar|mostrar)
    aplicar_familia iptables v4
    command -v ip6tables >/dev/null && aplicar_familia ip6tables v6
    if [ "$MODO" = "mostrar" ]; then
      echo
      echo "Nada foi aplicado. Rode com --aplicar para valer."
    else
      echo
      echo "Aplicado. Confira: de fora, 'curl -m 5 http://IP_DA_VPS' deve falhar;"
      echo "pelo domínio (via Cloudflare) deve responder."
    fi
    ;;
  *)
    echo "uso: $0 [--aplicar|--remover]" >&2
    exit 2
    ;;
esac
