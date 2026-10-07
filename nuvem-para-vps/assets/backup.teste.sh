#!/usr/bin/env bash
# Prova de restauração: um backup só existe depois de restaurado e contado.
#
# Baixa o backup mais recente do destino, restaura o MySQL num contêiner
# descartável SEM REDE (não encosta na produção) e compara a contagem exata de
# algumas tabelas com a produção. Rode antes do corte e depois toda semana.
set -euo pipefail

# ── CONFIGURAÇÃO ─────────────────────────────────────────────
DESTINO="remoto:meu-bucket-de-backup"
MYSQL_SERVICO="app_db"
MYSQL_SENHA_NO_CONTEINER=/run/secrets/mysql_root
MYSQL_IMAGEM="mysql:8.4.11"           # a mesma versão da produção
LIMITE_MEMORIA=4g                     # o teste roda na mesma máquina: não deixe ele disputar com a produção
LIMITE_CPU=2
ESPACO_MINIMO_GB=20
TABELAS="app.usuarios app.pedidos"    # banco.tabela que você quer conferir
# ─────────────────────────────────────────────────────────────

TMP="$(mktemp -d)"
# -v: leva junto o volume anônimo que a imagem do MySQL cria (senão sobra um por teste)
trap 'docker rm -fv teste-restauro >/dev/null 2>&1 || true; rm -rf "$TMP"' EXIT

livre_gb="$(df -Pk "$TMP" | awk 'NR==2{print int($4/1048576)}')"
if [ "$livre_gb" -lt "$ESPACO_MINIMO_GB" ]; then
  echo "só ${livre_gb} GB livres; o teste precisa de ${ESPACO_MINIMO_GB} GB" >&2
  exit 1
fi

ULTIMO="$(rclone lsf "$DESTINO" --dirs-only | sort | tail -n 1)"
[ -n "$ULTIMO" ] || { echo "nenhum backup no destino" >&2; exit 1; }
echo "restaurando $ULTIMO"
rclone copy "$DESTINO/$ULTIMO" "$TMP" --include "mysql.sql.gz" --include "SHA256SUMS"
( cd "$TMP" && grep ' ./mysql.sql.gz$' SHA256SUMS | sha256sum -c - )

docker run -d --name teste-restauro --network none --memory "$LIMITE_MEMORIA" --cpus "$LIMITE_CPU" \
  -e MYSQL_ROOT_PASSWORD=restauro -v "$TMP":/backup:ro "$MYSQL_IMAGEM" >/dev/null
for _ in $(seq 1 60); do
  docker exec teste-restauro mysqladmin -uroot -prestauro ping >/dev/null 2>&1 && break
  sleep 2
done
docker exec teste-restauro sh -c 'zcat /backup/mysql.sql.gz | mysql -uroot -prestauro'

PROD="$(docker ps -q -f "name=^${MYSQL_SERVICO}\." | head -1)"
falhas=0
for t in $TABELAS; do
  a="$(docker exec "$PROD" sh -c "MYSQL_PWD=\"\$(cat $MYSQL_SENHA_NO_CONTEINER)\" exec mysql -uroot -N -e 'SELECT COUNT(*) FROM $t'")"
  b="$(docker exec teste-restauro mysql -uroot -prestauro -N -e "SELECT COUNT(*) FROM $t" 2>/dev/null)"
  printf "  %-30s produção=%s restaurado=%s\n" "$t" "$a" "$b"
  # A produção pode ter crescido desde o backup: o restaurado não pode ter MAIS, nem estar vazio.
  if [ -z "$b" ] || [ "$b" -eq 0 ] || [ "$b" -gt "$a" ]; then falhas=$((falhas + 1)); fi
done

if [ "$falhas" -gt 0 ]; then
  echo "RESTAURAÇÃO FALHOU em $falhas tabela(s)" >&2
  exit 1
fi
echo "restauração ok ($ULTIMO)"
