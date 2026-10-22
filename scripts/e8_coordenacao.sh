#!/usr/bin/env bash
# E8 - Coordenacao e ordem.
#   Parte 1: sequencia de termos (epocas de lideranca) e revisoes (ordem total das escritas).
#   Parte 2: exclusao mutua com "etcdctl lock" entre worker1 e worker2; o detentor e derrubado
#            (docker kill) e mede-se o tempo ate o outro assumir quando o lease vence (5 repeticoes).
#   Parte 3: eleicao de lider de aplicacao com "etcdctl elect".
source "$(dirname "$0")/comum.sh"
SAIDA="$EVID/e8_coordenacao.txt"
LOGS="$TRAB/e8"; mkdir -p "$LOGS"   # logs brutos dos workers (arquivos de trabalho)

# Linha da tabela: evento | lider | termo | revisao
linha() {
  local de=${DE:-1} l rev
  l=$(lider "$de")
  rev=$(docker exec "etcd$de" etcdctl --endpoints="$EP" get /e8 -w json 2>/dev/null | grep -o '"revision":[0-9]*' | cut -d: -f2)
  printf "%-36s | etcd%-3s | %-5s | %s\n" "$1" "$l" "$(termo "$l")" "$rev"
}

epoch_ms() {
  docker exec cliente python -c "from datetime import datetime, timezone; \
print(int(datetime.fromisoformat('$1'[:26]).replace(tzinfo=timezone.utc).timestamp() * 1000))"
}

# Comando executado pelo etcdctl lock enquanto segura a trava (ETCD_LOCK_* vem do etcdctl)
SEGURA='echo "PEGOU $(hostname) chave=$ETCD_LOCK_KEY rev=$ETCD_LOCK_REV t_ms=$(python -c "import time; print(int(time.time()*1000))")"; sleep 3600'

{
  titulo "E8 - $(date '+%Y-%m-%d %H:%M:%S')"
  espera_saudavel

  titulo "Parte 1: termos e revisoes ao longo de escritas e falhas"
  printf "%-36s | %-7s | %-5s | %s\n" "evento" "lider" "termo" "revisao"
  linha "estado inicial"
  ctl 1 put /e8 a >/dev/null; linha "put /e8=a"
  ctl 2 put /e8 b >/dev/null; linha "put /e8=b (via outro membro)"
  L=$(lider); docker kill "etcd$L" >/dev/null; sleep 3
  S=$(( L % 3 + 1 ))
  DE=$S linha "lider etcd$L derrubado (docker kill)"
  DE=$S; ctl "$S" put /e8 c >/dev/null; linha "put /e8=c (sem o antigo lider)"
  docker start "etcd$L" >/dev/null; espera_saudavel; sleep 1
  linha "etcd$L volta (seguidor)"
  L=$(lider); docker kill "etcd$L" >/dev/null; sleep 3
  S=$(( L % 3 + 1 ))
  DE=$S linha "lider etcd$L derrubado (docker kill)"
  ctl "$S" put /e8 d >/dev/null; DE=$S linha "put /e8=d"
  docker start "etcd$L" >/dev/null; espera_saudavel; sleep 1
  unset DE; linha "cluster completo de novo"
  echo "historico de versoes da chave /e8 (cada put = nova revisao global):"
  ctl 1 get /e8 -w fields | grep -E "CreateRevision|ModRevision|Version"

  titulo "Parte 2: exclusao mutua com etcdctl lock (TTL padrao da sessao = 10 s), 5 repeticoes"
  : > "$TRAB/e8_lock"
  for r in 1 2 3 4 5; do
    docker start worker1 worker2 >/dev/null
    : > "$LOGS/lock_w1.log"; : > "$LOGS/lock_w2.log"
    docker exec worker1 etcdctl --endpoints="$EP" lock trava -- sh -c "$SEGURA" > "$LOGS/lock_w1.log" 2>&1 &
    espera_texto "$LOGS/lock_w1.log" PEGOU || continue
    docker exec worker2 etcdctl --endpoints="$EP" lock trava -- sh -c "$SEGURA" > "$LOGS/lock_w2.log" 2>&1 &
    sleep 2
    grep -q PEGOU "$LOGS/lock_w2.log" && echo "ERRO: worker2 pegou a trava junto com worker1!"
    docker kill worker1 >/dev/null
    espera_texto "$LOGS/lock_w2.log" PEGOU || continue
    t_kill=$(epoch_ms "$(docker inspect -f '{{.State.FinishedAt}}' worker1)")
    t_pegou=$(grep PEGOU "$LOGS/lock_w2.log" | sed 's/.*t_ms=//')
    echo $(( t_pegou - t_kill )) >> "$TRAB/e8_lock"
    echo "rodada $r: $(cut -d' ' -f1-4 "$LOGS/lock_w1.log") | worker1 morto -> $(cut -d' ' -f1-4 "$LOGS/lock_w2.log") apos $(( t_pegou - t_kill )) ms"
    # Encerra o comando que segura a trava; o etcdctl lock entao libera a trava e sai
    # (um "pkill etcdctl" nao basta: o etcdctl continua esperando o filho terminar)
    docker exec worker2 pkill -f "sleep 3600"
    wait 2>/dev/null
  done
  echo "tempo ate o outro worker assumir a trava (ms): $(estatisticas < "$TRAB/e8_lock")"
  echo "(rev = ETCD_LOCK_REV, revisao da chave da trava: cresce a cada novo detentor -> serve de fencing token)"

  titulo "Parte 3: eleicao de lider de aplicacao com etcdctl elect (sessao com TTL padrao de 60 s)"
  # nome novo a cada execucao para nao enxergar candidatos de execucoes anteriores
  ELEICAO="eleicao-$(date +%s)"
  docker start worker1 worker2 >/dev/null
  : > "$LOGS/elect_observador.log"
  docker exec cliente timeout 100 etcdctl --endpoints="$EP" elect -l "$ELEICAO" > "$LOGS/elect_observador.log" 2>&1 &
  docker exec worker1 etcdctl --endpoints="$EP" elect "$ELEICAO" "worker1-e-o-lider" > /dev/null 2>&1 &
  sleep 1
  docker exec worker2 etcdctl --endpoints="$EP" elect "$ELEICAO" "worker2-e-o-lider" > /dev/null 2>&1 &
  espera_texto "$LOGS/elect_observador.log" worker1-e-o-lider 10
  sleep 2
  echo "$(date +%H:%M:%S) candidatos: worker1 (primeiro, lider) e worker2; docker kill worker1"
  t0=$(date +%s)
  docker kill worker1 >/dev/null
  espera_texto "$LOGS/elect_observador.log" worker2-e-o-lider 80 \
    && echo "$(date +%H:%M:%S) worker2 virou lider ~$(( $(date +%s) - t0 )) s apos a queda (quando o lease de 60 s venceu)"
  docker restart -t 0 worker2 >/dev/null   # encerra o candidato restante
  docker exec cliente pkill -f "elect -l" 2>/dev/null
  wait 2>/dev/null
  echo "o que o observador (elect -l) viu, em ordem (chave do candidato e proposta):"
  cat "$LOGS/elect_observador.log"
  docker start worker1 >/dev/null
} 2>&1 | tee "$SAIDA"

echo; echo "Evidencia salva em $SAIDA"
