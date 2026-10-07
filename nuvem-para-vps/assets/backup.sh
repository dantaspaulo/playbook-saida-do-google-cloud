#!/usr/bin/env bash
# Backup diário da VPS: dump de cada banco, conferência, cópia para FORA da VPS.
#
# Ajuste a seção CONFIGURAÇÃO. Rode por um timer do systemd (melhor que cron:
# tem log e histórico) e com um vigia que avisa quando o backup do dia não chegou.
#
# Destino: um bucket de outro provedor via rclone (R2, S3, GCS, B2...). Use uma
# credencial que só CRIA objeto, sem apagar nem sobrescrever: se a VPS for
# invadida, o invasor não leva os backups junto. A retenção fica a cargo de uma
# regra de ciclo de vida do próprio bucket.
set -euo pipefail

# ── CONFIGURAÇÃO ─────────────────────────────────────────────
PASTA_LOCAL=/var/backups/vps          # cópia local (dias)
DIAS_LOCAIS=7
DESTINO="remoto:meu-bucket-de-backup" # nome do remote no rclone + bucket
MYSQL_SERVICO="app_db"                # nome do serviço no Swarm
MYSQL_SENHA_NO_CONTEINER=/run/secrets/mysql_root   # docker secret montado no serviço do banco
POSTGRES_SERVICOS=""                  # ex.: "hub_postgres chat_postgres"
VOLUMES=""                            # volumes a copiar em tar, ex.: "app_uploads"
# ─────────────────────────────────────────────────────────────

# Guarda: a limpeza no fim apaga pastas antigas daqui. Recusa caminho raso ou vazio.
case "$PASTA_LOCAL" in
  ""|"/"|/*/*) ;;
  *) echo "PASTA_LOCAL precisa ter ao menos dois níveis (ex.: /var/backups/vps)" >&2; exit 1 ;;
esac
[ "$PASTA_LOCAL" = "/" ] || [ -z "$PASTA_LOCAL" ] && { echo "PASTA_LOCAL inválida" >&2; exit 1; }

DIA="$(date -u +%Y-%m-%d)"
DIR="$PASTA_LOCAL/$DIA"
mkdir -p "$DIR"
chmod 700 "$PASTA_LOCAL"

conteiner() { docker ps -q -f "name=^${1}\." | head -1; }

if [ -n "$MYSQL_SERVICO" ]; then
  c="$(conteiner "$MYSQL_SERVICO")"; [ -n "$c" ] || { echo "MySQL não está rodando" >&2; exit 1; }
  # A senha é lida DENTRO do contêiner: não aparece no `ps` da máquina.
  docker exec -i "$c" sh -c "MYSQL_PWD=\"\$(cat $MYSQL_SENHA_NO_CONTEINER)\" exec mysqldump -uroot --all-databases --single-transaction --routines --triggers --events" \
    | gzip > "$DIR/mysql.sql.gz"
  # Recusa dump cortado: o mysqldump escreve esta linha só quando termina bem.
  zcat "$DIR/mysql.sql.gz" | tail -n 1 | grep -q "Dump completed" || { echo "dump do MySQL incompleto" >&2; exit 1; }
fi

for s in $POSTGRES_SERVICOS; do
  c="$(conteiner "$s")"; [ -n "$c" ] || { echo "$s não está rodando" >&2; exit 1; }
  docker exec -i "$c" pg_dumpall -U postgres | gzip > "$DIR/$s.sql.gz"
  [ "$(zcat "$DIR/$s.sql.gz" | wc -c)" -gt 1000 ] || { echo "dump de $s pequeno demais" >&2; exit 1; }
done

for v in $VOLUMES; do
  docker run --rm -v "$v":/origem:ro -v "$DIR":/destino alpine \
    tar -czf "/destino/volume-$v.tar.gz" -C /origem .
done

( cd "$DIR" && sha256sum ./* > SHA256SUMS )

# Sobe com o dia no caminho: nunca sobrescreve um backup anterior.
rclone copy "$DIR" "$DESTINO/$DIA" --immutable --checksum
rclone check "$DIR" "$DESTINO/$DIA" --one-way

# Só apaga pastas com nome de data, criadas por este script.
find "$PASTA_LOCAL" -mindepth 1 -maxdepth 1 -type d -name '20[0-9][0-9]-[0-9][0-9]-[0-9][0-9]' -mtime +"$DIAS_LOCAIS" -exec rm -rf {} +
echo "backup $DIA ok: $(du -sh "$DIR" | cut -f1)"
