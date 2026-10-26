#!/usr/bin/env bash
# Medicoes complementares (pedidas na revisao do relatorio):
#   Parte A: E3 - tempo de propagacao com 1 medicao de aquecimento DESCARTADA + 5 validas.
#   Parte B: E8 - eleicao de lider de aplicacao, 5 repeticoes, com candidatos que usam a API
#            de eleicao do etcd e lease de TTL 10 s (o "etcdctl elect" fixa a sessao em 60 s).
#            Mede-se o tempo entre a morte do lider (docker kill) e o outro candidato assumir.
source "$(dirname "$0")/comum.sh"
SAIDA="$EVID/e8b_medicoes_extras.txt"
LOGS="$TRAB/e8b"; mkdir -p "$LOGS"
TTL=10
CAND="python /app/enfase-b/candidato.py"

epoch_ms() {
  docker exec cliente python -c "from datetime import datetime, timezone; \
print(int(datetime.fromisoformat('$1'[:26]).replace(tzinfo=timezone.utc).timestamp() * 1000))"
}

{
  titulo "Medicoes extras - $(date '+%Y-%m-%d %H:%M:%S')"
  espera_saudavel

  titulo "Parte A: propagacao put no etcd1 -> leitura serializavel (1 aquecimento descartado + 5 medicoes)"
  for leitor in 2 3; do
    py propagacao "$(ip_de 1)" "$(ip_de "$leitor")" 6 > "$TRAB/e8b_prop_bruto"
    echo "aquecimento descartado (ms): $(head -n 1 "$TRAB/e8b_prop_bruto")"
    tail -n 5 "$TRAB/e8b_prop_bruto" > "$TRAB/e8b_prop"
    echo "etcd1 -> etcd$leitor (ms): $(estatisticas < "$TRAB/e8b_prop")"
  done

  titulo "Parte B: eleicao de lider de aplicacao (API de eleicao, lease TTL $TTL s), 5 repeticoes"
  : > "$TRAB/e8b_elect"
  for r in 1 2 3 4 5; do
    docker start worker1 worker2 >/dev/null
    ELEICAO="eleicao-$(date +%s)-$r"
    : > "$LOGS/w1.log"; : > "$LOGS/w2.log"
    docker exec worker1 $CAND worker1 172.31.0.31 "$ELEICAO" --ttl $TTL > "$LOGS/w1.log" 2>&1 &
    espera_texto "$LOGS/w1.log" LIDER 15 || continue
    docker exec worker2 $CAND worker2 172.31.0.32 "$ELEICAO" --ttl $TTL > "$LOGS/w2.log" 2>&1 &
    espera_texto "$LOGS/w2.log" CANDIDATO 15 || continue
    sleep 2
    grep -q LIDER "$LOGS/w2.log" && echo "ERRO: dois lideres ao mesmo tempo!"
    docker kill worker1 >/dev/null
    espera_texto "$LOGS/w2.log" LIDER 30 || continue
    t_kill=$(epoch_ms "$(docker inspect -f '{{.State.FinishedAt}}' worker1)")
    t_lider=$(grep LIDER "$LOGS/w2.log" | sed 's/.*t_ms=//')
    echo $(( t_lider - t_kill )) >> "$TRAB/e8b_elect"
    echo "rodada $r: $(grep LIDER "$LOGS/w1.log" | cut -d' ' -f1-3) | worker1 morto -> $(grep LIDER "$LOGS/w2.log" | cut -d' ' -f1-3) apos $(( t_lider - t_kill )) ms"
    docker exec worker2 pkill -f candidato.py 2>/dev/null
    wait 2>/dev/null
  done
  docker start worker1 >/dev/null
  echo "tempo ate o outro candidato assumir a lideranca (ms): $(estatisticas < "$TRAB/e8b_elect")"
} 2>&1 | tee "$SAIDA"

echo; echo "Evidencia salva em $SAIDA"
