#!/usr/bin/env bash
# E4 - Consistencia: leitura linearizavel (padrao) x serializavel.
#   Parte 1: latencia das duas leituras em condicoes normais (5 rodadas).
#   Parte 2: seguidor isolado da rede interna; escrita pelo lado majoritario;
#            leitura no isolado com as duas consistencias (sequencia temporal).
source "$(dirname "$0")/comum.sh"
SAIDA="$EVID/e4_consistencia.txt"

# Le /config/modo no membro $1 com as duas consistencias e imprime uma linha da tabela
le_nos_dois_modos() {
  local n=$1 lin ser
  lin=$(ctl "$n" --command-timeout=3s get /config/modo --print-value-only 2>&1 | tail -1)
  ser=$(ctl "$n" --command-timeout=3s get /config/modo --print-value-only --consistency=s 2>&1 | tail -1)
  printf "%s  %-28s | etcd%s linearizavel: %-40s | serializavel: %s\n" "$(date +%H:%M:%S)" "$2" "$n" "$lin" "$ser"
}

{
  L=$(lider)
  for n in 1 2 3; do [ "$n" != "$L" ] && { F=$n; break; }; done
  titulo "E4 - $(date '+%Y-%m-%d %H:%M:%S')   lider = etcd$L   seguidor observado = etcd$F"

  titulo "Parte 1: latencia de get no seguidor etcd$F (50 leituras por rodada, 5 rodadas)"
  : > /tmp/e4_l; : > /tmp/e4_s
  for r in 1 2 3 4 5; do
    linha=$(py latencia "$(ip_de "$F")" 50);   echo "${linha#*get_ms=}" >> /tmp/e4_l
    linha=$(py latencia "$(ip_de "$F")" 50 s); echo "${linha#*get_ms=}" >> /tmp/e4_s
  done
  echo "linearizavel (ms): $(estatisticas < /tmp/e4_l)"
  echo "serializavel (ms): $(estatisticas < /tmp/e4_s)"
  echo "(linearizavel consulta o lider via ReadIndex antes de responder; serializavel le o estado local)"

  titulo "Parte 2: sequencia temporal com o seguidor etcd$F isolado"
  ctl "$L" put /config/modo "v1-normal" >/dev/null
  le_nos_dois_modos "$F" "apos put v1 (sem particao)"

  isola "$F" >/dev/null
  echo "$(date +%H:%M:%S)  >>> etcd$F isolado da rede interna (continua acessivel ao cliente)"
  sleep 2

  echo "$(date +%H:%M:%S)  put v2 pelo lider etcd$L: $(ctl "$L" put /config/modo "v2-durante-particao")"
  le_nos_dois_modos "$F" "apos put v2 (isolado)"
  echo "$(date +%H:%M:%S)  put v3 pelo lider etcd$L: $(ctl "$L" put /config/modo "v3-durante-particao")"
  le_nos_dois_modos "$F" "apos put v3 (isolado)"
  for n in 1 2 3; do [ "$n" != "$F" ] && le_nos_dois_modos "$n" "lado majoritario"; done

  reconecta "$F" >/dev/null
  echo "$(date +%H:%M:%S)  >>> etcd$F reconectado"
  espera_saudavel; sleep 1
  le_nos_dois_modos "$F" "apos reconexao"
} 2>&1 | tee "$SAIDA"

echo; echo "Evidencia salva em $SAIDA"
