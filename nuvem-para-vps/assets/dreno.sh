#!/bin/sh
# Segura o SIGTERM por alguns segundos antes de repassar para a aplicação.
#
# Por quê: no deploy, o proxy (Traefik) leva alguns segundos para perceber que a
# réplica está saindo. Se a aplicação fecha na hora do SIGTERM, as requisições
# desse intervalo voltam com erro. Esperando ~20 s, a réplica continua atendendo
# enquanto sai da roleta, e só então fecha.
#
# Uso: entrypoint ["/dreno.sh"] + command [o comando da aplicação]
#      stop_grace_period maior que DRENO_SEGUNDOS + o tempo de a aplicação fechar.
ESPERA="${DRENO_SEGUNDOS:-20}"

"$@" &
PID=$!

repassar() {
  sleep "$ESPERA"
  kill -TERM "$PID" 2>/dev/null
}
trap repassar TERM INT

wait "$PID"      # volta quando chega o sinal (o trap roda)...
wait "$PID"      # ...e aqui espera a aplicação terminar de fechar
