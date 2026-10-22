#!/usr/bin/env bash
# E3 - Replicacao: escrever em um membro, ler em outro, watch em um terceiro;
# latencia de put/get e tempo de propagacao (5 repeticoes) e check perf.
source "$(dirname "$0")/comum.sh"
SAIDA="$EVID/e3_replicacao.txt"

{
  titulo "E3 - $(date '+%Y-%m-%d %H:%M:%S')   lider = etcd$(lider)"

  titulo "watch no etcd3, put no etcd1, get no etcd2 (endpoints unicos)"
  docker exec cliente timeout 6 etcdctl --endpoints=172.31.0.33:2379 watch /config/ --prefix -w json \
    > "$EVID/e3_watch.log" 2>&1 &
  sleep 2
  valor="v-$(date +%H%M%S)"
  echo "put em etcd1: /config/versao = $valor"
  ctl 1 put /config/versao "$valor"
  echo "get em etcd2: $(ctl 2 get /config/versao --print-value-only)"
  wait
  echo "notificacao recebida pelo watch no etcd3:"
  cat "$EVID/e3_watch.log"

  titulo "Latencia de put e get linearizavel (50 operacoes por rodada, 5 rodadas)"
  for alvo in 1 2 3; do
    : > "$TRAB/e3_put"; : > "$TRAB/e3_get"
    for r in 1 2 3 4 5; do
      linha=$(py latencia "$(ip_de "$alvo")" 50)
      echo "${linha#*put_ms=}" | awk '{ print $1 }' >> "$TRAB/e3_put"
      echo "${linha#*get_ms=}" >> "$TRAB/e3_get"
    done
    papel="seguidor"; [ "$alvo" = "$(lider)" ] && papel="LIDER"
    echo "etcd$alvo ($papel)  put (ms): $(estatisticas < "$TRAB/e3_put")"
    echo "etcd$alvo ($papel)  get (ms): $(estatisticas < "$TRAB/e3_get")"
  done

  titulo "Tempo de propagacao: put no etcd1, leitura serializavel (local) no etcd2 e no etcd3"
  for leitor in 2 3; do
    py propagacao "$(ip_de 1)" "$(ip_de "$leitor")" 5 > "$TRAB/e3_prop"
    echo "etcd1 -> etcd$leitor (ms): $(estatisticas < "$TRAB/e3_prop")"
  done

  titulo "etcdctl check perf --load=s (referencia de desempenho, ~60 s)"
  # a barra de progresso usa \r; fica so o resultado final
  ctl_todos check perf --load=s | tr '\r' '\n' | grep -E "PASS|FAIL|Slowest|Throughput|Stddev"
} 2>&1 | tee "$SAIDA"

echo; echo "Evidencia salva em $SAIDA"
