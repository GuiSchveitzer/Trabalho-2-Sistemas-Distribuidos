#!/usr/bin/env bash
# E7 - Recuperacao por log: o lider e isolado, a maioria recebe 1000 escritas, o membro e
# reconectado e volta como SEGUIDOR (termo atualizado) alcancando o mesmo RAFT INDEX.
# 5 repeticoes. A recuperacao por snapshot esta em e7b_snapshot.sh.
source "$(dirname "$0")/comum.sh"
SAIDA="$EVID/e7_recuperacao.txt"

{
  titulo "E7 - $(date '+%Y-%m-%d %H:%M:%S')   recuperacao por log (5 repeticoes)"
  : > "$TRAB/e7_alc"
  for r in 1 2 3 4 5; do
    espera_saudavel; sleep 2
    L=$(lider)
    t_isola=$(isola "$L")
    sleep 3   # maioria elege novo lider
    N=$(DE=$(( L % 3 + 1 )) lider)
    py carga "$(ip_de "$N")" 3000 1000 >/dev/null

    : > "$TRAB/e7_med"
    py alcanca "$(ip_de "$L")" "$(ip_de "$N")" > "$TRAB/e7_med" &
    espera_texto "$TRAB/e7_med" pronto || continue
    t_religa=$(reconecta "$L")
    wait
    res=$(grep t_fim_ms "$TRAB/e7_med")
    t_fim=$(echo "$res" | sed 's/t_fim_ms=\([0-9]*\).*/\1/')
    echo $(( t_fim - t_religa )) >> "$TRAB/e7_alc"
    echo "rodada $r: etcd$L isolado (era lider) por $(( t_religa - t_isola )) ms, novo lider etcd$N -> recuperado em $(( t_fim - t_religa )) ms (${res#* })"
  done
  echo "tempo da reconexao ate aplicar todas as entradas (ms): $(estatisticas < "$TRAB/e7_alc")"

  # Durante a particao a conexao TCP entre os pares nao cai (fica meio aberta); o lider continua
  # enviando e o TCP retransmite com backoff exponencial (RTO minimo de 200 ms no Linux:
  # retransmissoes ~0.2, 0.6, 1.4, 3.0, 6.2, 12.6, 25.4 s apos a primeira perda). Ao religar, o
  # trafego so volta na proxima retransmissao. Hipotese: espera = proxima retransmissao - duracao.
  titulo "Varredura: duracao da particao x tempo de recuperacao (hipotese do backoff do TCP)"
  printf "%-12s | %-14s | %-14s | %s\n" "alvo (s)" "particao (ms)" "medido (ms)" "previsto pelo backoff (ms)"
  for D in 4 8 11 14 20; do
    espera_saudavel; sleep 2
    L=$(lider)
    t_isola=$(isola "$L"); h0=$(date +%s%3N)
    sleep 3
    N=$(DE=$(( L % 3 + 1 )) lider)
    py carga "$(ip_de "$N")" 200 100 >/dev/null
    : > "$TRAB/e7_med"
    py alcanca "$(ip_de "$L")" "$(ip_de "$N")" > "$TRAB/e7_med" &
    espera_texto "$TRAB/e7_med" pronto || continue
    resta=$(( D * 1000 - ($(date +%s%3N) - h0) ))
    [ "$resta" -gt 0 ] && sleep "$(awk "BEGIN { print $resta / 1000 }")"
    t_religa=$(reconecta "$L")
    wait
    t_fim=$(grep t_fim_ms "$TRAB/e7_med" | sed 's/t_fim_ms=\([0-9]*\).*/\1/')
    dur=$(( t_religa - t_isola ))
    prev=$(awk -v d="$dur" 'BEGIN { split("200 600 1400 3000 6200 12600 25400 51000", s, " ");
                                    for (i = 1; i <= 8; i++) if (s[i] > d) { print s[i] - d; exit } }')
    printf "%-12s | %-14s | %-14s | %s\n" "$D" "$dur" "$(( t_fim - t_religa ))" "$prev"
  done

  espera_saudavel; sleep 1
  titulo "estado final: mesmo RAFT INDEX e mesmo conteudo nos 3 membros"
  ctl_todos endpoint status -w table
  for n in 1 2 3; do
    echo "etcd$n: $(ctl "$n" get /carga/ --prefix --count-only --consistency=s -w fields | grep Count) chaves /carga/  hash=$(ctl "$n" endpoint hashkv -w simple | awk -F', ' '{ print $2 }')"
  done
  echo "(hashkv igual = estado identico nas replicas)"

  titulo "trecho do log do ultimo membro reconectado"
  docker logs --since 40s "etcd$L" 2>&1 | grep -iE "became follower|elected leader|lost leader|peer.*active" | tail -6
} 2>&1 | tee "$SAIDA"

echo; echo "Evidencia salva em $SAIDA"
