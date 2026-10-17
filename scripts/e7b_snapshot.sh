#!/usr/bin/env bash
# E7 (parte 2) - Recuperacao por SNAPSHOT.
# Recria o cluster com --snapshot-count=1000, para um seguidor, faz 12000 escritas e religa o
# seguidor: o lider ja compactou o log que o seguidor precisaria, entao envia um snapshot.
# ATENCAO: recria os 3 membros (apaga os dados) no inicio e no fim.
source "$(dirname "$0")/comum.sh"
SAIDA="$EVID/e7b_snapshot.txt"

# Converte um timestamp do Docker (RFC 3339 com nanossegundos) em epoch ms
epoch_ms() {
  docker exec cliente python -c "from datetime import datetime, timezone; \
print(int(datetime.fromisoformat('$1'[:26]).replace(tzinfo=timezone.utc).timestamp() * 1000))"
}

{
  titulo "E7b - $(date '+%Y-%m-%d %H:%M:%S')   recuperacao por snapshot"
  cd "$RAIZ"
  SNAPSHOT_COUNT=1000 docker compose up -d --force-recreate etcd1 etcd2 etcd3 2>&1 | grep -c Started
  espera_saudavel; sleep 2
  L=$(lider); for n in 1 2 3; do [ "$n" != "$L" ] && { F=$n; break; }; done
  echo "cluster recriado com ETCD_SNAPSHOT_COUNT=1000 | lider etcd$L | seguidor que vai parar: etcd$F"

  docker stop "etcd$F" >/dev/null
  echo "$(date +%H:%M:%S) etcd$F parado; escrevendo 12000 chaves pelo lider..."
  py carga "$(ip_de "$L")" 12000 100
  DE=$L ctl_todos endpoint status -w table 2>&1 | grep -v "deadline"

  : > /tmp/e7b_med
  py alcanca "$(ip_de "$F")" "$(ip_de "$L")" > /tmp/e7b_med &
  sleep 1
  docker start "etcd$F" >/dev/null
  wait
  res=$(grep t_fim_ms /tmp/e7b_med)
  t_fim=$(echo "$res" | sed 's/t_fim_ms=\([0-9]*\).*/\1/')
  t_ini=$(epoch_ms "$(docker inspect -f '{{.State.StartedAt}}' "etcd$F")")
  echo "etcd$F recuperado $(( t_fim - t_ini )) ms apos o processo iniciar (${res#* })"

  titulo "logs do LIDER etcd$L (envio do snapshot)"
  docker logs "etcd$L" 2>&1 | grep -iE "sending database snapshot|sent database snapshot|snapshot.*to.*$(id_de "$F")" | tail -4 | cut -c1-260
  titulo "logs do SEGUIDOR etcd$F (recebimento e aplicacao)"
  docker logs "etcd$F" 2>&1 | grep -iE "received and saved database snapshot|applying snapshot|applied snapshot|restored" | tail -5 | cut -c1-260

  titulo "estado final"
  ctl_todos endpoint status -w table
  for n in 1 2 3; do echo "etcd$n hashkv=$(ctl "$n" endpoint hashkv -w simple | awk -F', ' '{ print $2 }')"; done

  titulo "restaurando o cluster com snapshot-count padrao (recria os membros)"
  docker compose up -d --force-recreate etcd1 etcd2 etcd3 2>&1 | grep -c Started
  espera_saudavel && echo "cluster saudavel, lider etcd$(lider)"
} 2>&1 | tee "$SAIDA"

echo; echo "Evidencia salva em $SAIDA"
