#!/usr/bin/env bash
# E5 - Falha e quorum.
#   Parte 1: derruba o lider (docker kill = queda abrupta) e mede o tempo de eleicao (5 repeticoes).
#   Parte 2: docker stop (desligamento gracioso) do lider: o etcd transfere a lideranca antes de sair.
#   Parte 3: quadro "membros ativos x leitura linearizavel x leitura serializavel x escrita".
source "$(dirname "$0")/comum.sh"
SAIDA="$EVID/e5_falha_quorum.txt"

# Testa escrita e as duas leituras no membro $1; imprime OK/FALHA
testa_membro() {
  local n=$1 w l s
  ctl "$n" --command-timeout=3s put /e5/teste "$(date +%s)" >/dev/null 2>&1 && w=OK || w=FALHA
  ctl "$n" --command-timeout=3s get /e5/teste >/dev/null 2>&1 && l=OK || l=FALHA
  ctl "$n" --command-timeout=3s get /e5/teste --consistency=s >/dev/null 2>&1 && s=OK || s=FALHA
  printf "%-16s | %-8s | %-20s | %-20s | %s\n" "$2" "etcd$n" "$l" "$s" "$w"
}

{
  titulo "E5 - $(date '+%Y-%m-%d %H:%M:%S')"

  titulo "Parte 1: queda abrupta do lider (docker kill), 5 repeticoes"
  : > "$TRAB/e5_eleicao"
  for r in 1 2 3 4 5; do
    espera_saudavel; sleep 3
    L=$(lider); S=(); for n in 1 2 3; do [ "$n" != "$L" ] && S+=("$n"); done
    : > "$TRAB/e5_med"   # zera para nao achar o "pronto" da rodada anterior
    py eleicao "$(ip_de "$L")" "$(ip_de "${S[0]}")" "$(ip_de "${S[1]}")" > "$TRAB/e5_med" &
    espera_texto "$TRAB/e5_med" pronto || continue
    docker kill "etcd$L" >/dev/null
    wait
    res=$(grep eleicao_ms "$TRAB/e5_med")
    [ -n "$res" ] && echo "${res#eleicao_ms=}" | awk '{ print $1 }' >> "$TRAB/e5_eleicao"
    escrita=$(ctl "${S[0]}" --command-timeout=3s put /e5/apos_queda "r$r" 2>&1)
    echo "rodada $r: lider etcd$L derrubado -> $res | escrita com 2 de 3: $escrita"
    docker start "etcd$L" >/dev/null
  done
  echo "tempo de eleicao (ms): $(estatisticas < "$TRAB/e5_eleicao")"
  echo "(election timeout padrao do etcd = 1000 ms + sorteio; heartbeat = 100 ms)"

  titulo "Parte 2: docker stop (gracioso) do lider -> transferencia de lideranca"
  espera_saudavel; sleep 2
  L=$(lider); echo "lider = etcd$L, termo $(termo "$L")"
  docker stop "etcd$L" >/dev/null
  docker logs "etcd$L" 2>&1 | grep -iE "leadership transfer|transferee|transfer-leadership" | tail -4
  docker start "etcd$L" >/dev/null; espera_saudavel; sleep 1
  echo "novo lider = etcd$(lider), termo $(termo "$(lider)")"

  titulo "Parte 3: membros ativos x leitura x escrita (testado sempre no etcd1)"
  espera_saudavel; sleep 1
  printf "%-16s | %-8s | %-20s | %-20s | %s\n" "membros ativos" "membro" "leitura linearizavel" "leitura serializavel" "escrita"
  testa_membro 1 "3 (todos)"
  docker stop etcd3 >/dev/null
  sleep 2; testa_membro 1 "2 (etcd3 parado)"
  docker stop etcd2 >/dev/null
  sleep 2; testa_membro 1 "1 (so etcd1)"
  echo
  echo "mensagem da escrita sem quorum:"
  ctl 1 --command-timeout=3s put /e5/teste "sem-quorum" 2>&1 | tail -1
  echo "endpoint status do etcd1 sozinho (sem lider: termo segue, ninguem e lider):"
  ctl 1 endpoint status -w table 2>&1
  docker start etcd2 etcd3 >/dev/null
  espera_saudavel
  echo "cluster restaurado: lider = etcd$(lider)"
} 2>&1 | tee "$SAIDA"

echo; echo "Evidencia salva em $SAIDA"
