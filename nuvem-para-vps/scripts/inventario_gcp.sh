#!/usr/bin/env bash
# Inventário de um projeto do Google Cloud, SÓ com comandos de leitura.
# Uso: bash inventario_gcp.sh PROJETO [PASTA_SAIDA]
#
# Nada aqui cria, muda ou apaga recurso. A saída fica na sua máquina e tem
# nomes internos: não publique a pasta.
set -u
PROJETO="${1:-}"
SAIDA="${2:-./inventario}"
if [ -z "$PROJETO" ]; then
  echo "uso: bash inventario_gcp.sh PROJETO [PASTA_SAIDA]" >&2
  exit 2
fi
command -v gcloud >/dev/null || { echo "gcloud não instalado" >&2; exit 2; }
# Sem perguntas: se uma API estiver desligada, o gcloud oferece ligá-la; aqui a
# resposta é sempre "não" (ligar API muda o projeto, e inventário só lê).
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
mkdir -p "$SAIDA"
echo "Projeto: $PROJETO · conta ativa: $(gcloud config get-value account 2>/dev/null)"
echo "Confira se a conta é a certa para este projeto antes de seguir."

# Cada linha: arquivo | comando (todos list/describe)
rodar() {
  local arq="$1"; shift
  if "$@" --project "$PROJETO" > "$SAIDA/$arq.txt" 2> "$SAIDA/$arq.erro"; then
    local n; n=$(($(wc -l < "$SAIDA/$arq.txt") - 1)); [ "$n" -lt 0 ] && n=0
    printf "  %-22s %s linha(s)\n" "$arq" "$n"
    rm -f "$SAIDA/$arq.erro"
  else
    printf "  %-22s (sem acesso ou API desligada: veja %s.erro)\n" "$arq" "$arq"
  fi
}

echo "== Computação"
rodar vms            gcloud compute instances list --format="table(name,zone.basename(),machineType.basename(),status)"
rodar discos         gcloud compute disks list --format="table(name,zone.basename(),sizeGb,type.basename(),users.len():label=USADO_POR)"
rodar snapshots      gcloud compute snapshots list --format="table(name,diskSizeGb,storageBytes,creationTimestamp.date())"
rodar ips            gcloud compute addresses list --format="table(name,region.basename(),addressType,status,users.len():label=USADO_POR)"
rodar encaminhamento gcloud compute forwarding-rules list --format="table(name,region.basename(),loadBalancingScheme,target.basename())"
rodar imagens        gcloud compute images list --no-standard-images --format="table(name,diskSizeGb,creationTimestamp.date())"
echo "== Dados"
rodar cloudsql       gcloud sql instances list --format="table(name,databaseVersion,settings.tier,settings.dataDiskSizeGb,state)"
rodar redis          gcloud redis instances list --region=- --format="table(name,tier,memorySizeGb,state)"
rodar buckets        gcloud storage buckets list --format="table(name,location,storageClass)"
echo "== Serverless e containers"
rodar cloudrun       gcloud run services list --format="table(metadata.name,region,status.url)"
rodar funcoes        gcloud functions list --format="table(name,state,environment)"
rodar gke            gcloud container clusters list --format="table(name,location,currentNodeCount,status)"
echo "== Outros"
rodar dns            gcloud dns managed-zones list --format="table(name,dnsName,visibility)"
# O agendador não aceita "todas as regiões": percorre as que existem no projeto.
: > "$SAIDA/agendador.txt"
for loc in $(gcloud scheduler locations list --project "$PROJETO" --format="value(locationId)" 2>/dev/null); do
  gcloud scheduler jobs list --location="$loc" --project "$PROJETO" \
    --format="table[no-heading](name.basename(),schedule,state)" 2>/dev/null >> "$SAIDA/agendador.txt"
done
printf "  %-22s %s linha(s)\n" agendador "$(grep -c . "$SAIDA/agendador.txt" || true)"
rodar segredos       gcloud secrets list --format="table(name.basename(),createTime.date())"
rodar pubsub         gcloud pubsub topics list --format="table(name.basename())"

echo "== Tamanho dos buckets (pode demorar em bucket grande)"
if [ -s "$SAIDA/buckets.txt" ]; then
  tail -n +2 "$SAIDA/buckets.txt" | awk '{print $1}' | while read -r b; do
    [ -z "$b" ] && continue
    tam=$(gcloud storage du -s "gs://$b" --project "$PROJETO" 2>/dev/null | awk '{print $1}')
    printf "  %-40s %s bytes\n" "$b" "${tam:-?}"
  done | tee "$SAIDA/buckets-tamanho.txt"
fi

echo
echo "Pronto: $SAIDA/. Olhe primeiro: discos com USADO_POR=0, IPs com USADO_POR=0,"
echo "snapshots antigos e VMs paradas que ainda cobram disco."
