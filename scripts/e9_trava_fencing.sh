#!/usr/bin/env bash
# E9 - Enfase B: travas, leases e fencing.
#   Cenario 0: dois workers disputam a trava normalmente -> exclusao mutua funciona.
#   Cenario 1: o detentor e congelado (docker pause) alem do TTL, SEM fencing -> violacao.
#   Cenario 2: mesmo roteiro, COM fencing token (revisao da chave) -> escrita atrasada rejeitada.
#   Cenario 3: pausa MENOR que o TTL -> o lease sobrevive e nao ha violacao (caso limite).
#   rep:       cenarios 1 e 2 repetidos 5 vezes cada, com estatisticas.
# Uso: scripts/e9_trava_fencing.sh [0|1|2|3|rep ...]   (sem argumento roda 0 1 2 3 rep)
source "$(dirname "$0")/comum.sh"
LOGS="$TRAB/e9"     # logs brutos dos workers (arquivos de trabalho)
mkdir -p "$LOGS" "$EVID/e9"

TTL=5
WORKER="python /app/enfase-b/worker.py"
recurso() { docker exec cliente python /app/enfase-b/recurso.py "$@"; }

cenario_normal() {
  titulo "Cenario 0: dois workers, 5 incrementos cada, sem falhas"
  recurso reset 0
  docker exec worker1 $WORKER worker1 172.31.0.31 --ttl $TTL --iteracoes 5 --trabalho 0.3 > "$LOGS/c0_worker1.log" &
  docker exec worker2 $WORKER worker2 172.31.0.32 --ttl $TTL --iteracoes 5 --trabalho 0.3 > "$LOGS/c0_worker2.log" &
  wait
  sort -k1,1 "$LOGS"/c0_worker*.log
  echo; recurso historico
  echo "Esperado: valor final 10 (nenhuma atualizacao perdida)."
}

# $1 = 0 (sem fencing) ou 1 (com fencing); $2 = prefixo dos logs
# Imprime no fim uma linha "RESUMO valor_final=... tomada_ms=..." para o modo rep
cenario_pausa() {
  local fencing=$1 pre=$2
  recurso reset "$fencing"

  # worker1 pega a trava, le o valor e entra no "processamento" de 2 s
  docker exec worker1 $WORKER worker1 172.31.0.31 --ttl $TTL --iteracoes 1 --trabalho 2 > "$LOGS/${pre}_worker1.log" &
  local pid1=$!
  espera_texto "$LOGS/${pre}_worker1.log" processando || return

  # Congela worker1 DENTRO da secao critica (simula pausa de GC, VM migrada, swap...)
  docker pause worker1 >/dev/null
  echo "$(date '+%H:%M:%S') >>> docker pause worker1 (congelado dentro da secao critica)"

  # worker2 fica esperando a trava; ela so e liberada quando o lease de worker1 vencer (TTL)
  docker exec worker2 $WORKER worker2 172.31.0.32 --ttl $TTL --iteracoes 3 --trabalho 0.3 > "$LOGS/${pre}_worker2.log"

  # worker1 acorda achando que ainda tem a trava e escreve o valor que leu antes da pausa
  echo "$(date '+%H:%M:%S') >>> docker unpause worker1"
  docker unpause worker1 >/dev/null
  wait $pid1

  echo; echo "--- linha do tempo dos workers ---"
  sort -k1,1 "$LOGS/${pre}_worker1.log" "$LOGS/${pre}_worker2.log"
  echo; echo "--- historico do recurso ---"
  recurso historico

  # Tomada da trava medida no relogio dos conteineres: ultima renovacao do lease de worker1 -> trava de worker2
  local t_renov t_tomada valor
  t_renov=$(grep -o "ultima_renovacao_ms=[0-9]*" "$LOGS/${pre}_worker1.log" | cut -d= -f2)
  t_tomada=$(grep -m1 "TRAVA obtida" "$LOGS/${pre}_worker2.log" | sed 's/.*t_ms=//')
  valor=$(recurso historico | grep -o "valor final = [0-9]*" | grep -o "[0-9]*$")
  echo "worker2 obteve a trava $(( t_tomada - t_renov )) ms apos a ULTIMA renovacao do lease de worker1 (TTL = ${TTL}000 ms)"
  echo "RESUMO valor_final=$valor tomada_ms=$(( t_tomada - t_renov ))"
}

# Caso limite: pausa de 2 s, menor que o TTL de 5 s
cenario_pausa_curta() {
  titulo "Cenario 3: pausa de 2 s (MENOR que o TTL de ${TTL} s), sem fencing"
  recurso reset 0
  docker exec worker1 $WORKER worker1 172.31.0.31 --ttl $TTL --iteracoes 1 --trabalho 2 > "$LOGS/c3_worker1.log" &
  espera_texto "$LOGS/c3_worker1.log" processando || return
  docker pause worker1 >/dev/null
  echo "$(date '+%H:%M:%S') >>> docker pause worker1 por 2 s"
  docker exec worker2 $WORKER worker2 172.31.0.32 --ttl $TTL --iteracoes 3 --trabalho 0.3 > "$LOGS/c3_worker2.log" &
  sleep 2
  docker unpause worker1 >/dev/null
  echo "$(date '+%H:%M:%S') >>> docker unpause worker1"
  wait
  echo; echo "--- linha do tempo dos workers ---"
  sort -k1,1 "$LOGS/c3_worker1.log" "$LOGS/c3_worker2.log"
  echo; echo "--- historico do recurso ---"
  recurso historico
  echo "Esperado: valor final 4 (1 + 3). O lease nao venceu, entao worker2 esperou worker1 liberar a trava."
}

repeticoes() {
  titulo "Repeticoes: cenarios 1 (sem fencing) e 2 (com fencing), 5 vezes cada"
  for f in 0 1; do
    : > /tmp/e9_tomada; viol=0; rej=0
    for r in 1 2 3 4 5; do
      saida=$(cenario_pausa "$f" "rep_f${f}_r$r" 2>&1)
      echo "$saida" > "$EVID/e9/rep_f${f}_r$r.txt"   # prova detalhada de cada repeticao
      resumo=$(echo "$saida" | grep RESUMO)
      echo "$resumo" | grep -o "tomada_ms=[0-9]*" | cut -d= -f2 >> /tmp/e9_tomada
      echo "$saida" | grep -q "VIOLACAO" && viol=$((viol + 1))
      echo "$saida" | grep -q "REJEITADA  worker1" && rej=$((rej + 1))
      echo "fencing=$f rodada $r: $resumo"
    done
    echo "fencing=$f: violacoes=$viol/5  escritas atrasadas rejeitadas=$rej/5"
    echo "fencing=$f: tomada da trava apos a ultima renovacao (ms): $(estatisticas < /tmp/e9_tomada)"
  done
}

executar() {
  case $1 in
    0) cenario_normal ;;
    1) titulo "Cenario 1: pausa do detentor alem do TTL, SEM fencing"
       cenario_pausa 0 c1
       echo "Esperado: 4 incrementos (1 de worker1 + 3 de worker2), mas o valor final e 1: violacao." ;;
    2) titulo "Cenario 2: pausa do detentor alem do TTL, COM fencing token"
       cenario_pausa 1 c2
       echo "Esperado: a escrita atrasada de worker1 (token menor) e rejeitada; valor final 3, sem regressao." ;;
    3) cenario_pausa_curta ;;
    rep) repeticoes ;;
  esac
}

espera_saudavel
for c in ${@:-0 1 2 3 rep}; do
  executar "$c" 2>&1 | tee "$EVID/e9_cenario$c.txt"
done
