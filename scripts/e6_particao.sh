#!/usr/bin/env bash
# E6 - Particao de rede: o LIDER e isolado da rede interna, mas continua acessivel ao cliente.
# Observa os dois lados: majoria elege novo lider (termo maior); o antigo para de aceitar escritas.
source "$(dirname "$0")/comum.sh"
SAIDA="$EVID/e6_particao.txt"

# Escrita e leituras no membro $1; imprime o resultado de cada operacao
testa() {
  local n=$1
  echo "  etcd$n put            : $(ctl "$n" --command-timeout=3s put /config/modo "$2" 2>&1 | tail -1)"
  echo "  etcd$n get linearizavel: $(ctl "$n" --command-timeout=3s get /config/modo --print-value-only 2>&1 | tail -1)"
  echo "  etcd$n get serializavel: $(ctl "$n" --command-timeout=3s get /config/modo --print-value-only --consistency=s 2>&1 | tail -1)"
}

{
  espera_saudavel
  L=$(lider); M=(); for n in 1 2 3; do [ "$n" != "$L" ] && M+=("$n"); done
  titulo "E6 - $(date '+%Y-%m-%d %H:%M:%S')   lider = etcd$L   maioria = etcd${M[0]}, etcd${M[1]}"
  ctl "$L" put /config/modo "antes-da-particao" >/dev/null

  titulo "antes da particao"
  ctl_todos endpoint status -w table

  isola "$L" >/dev/null
  inicio=$(date +%s)
  echo "$(date +%H:%M:%S) >>> etcd$L (lider) isolado da rede interna"
  sleep 4

  titulo "durante a particao (endpoint status consultado pela rede de clientes)"
  ctl_todos endpoint status -w table 2>&1

  titulo "lado MAJORITARIO (etcd${M[0]})"
  testa "${M[0]}" "escrito-pela-maioria"

  titulo "lado MINORITARIO (etcd$L, antigo lider) - cliente conectado so a ele"
  testa "$L" "escrito-pelo-isolado"

  titulo "logs do antigo lider durante a particao (check quorum / pre-vote)"
  docker logs --since "$(( $(date +%s) - inicio + 2 ))s" "etcd$L" 2>&1 \
    | grep -iE "stepped down|lost leader|became|pre-vote|campaign|leader" | head -12

  reconecta "$L" >/dev/null
  echo; echo "$(date +%H:%M:%S) >>> etcd$L reconectado"
  espera_saudavel; sleep 1
  titulo "depois da reconexao (o antigo lider volta como seguidor, com termo atualizado)"
  ctl_todos endpoint status -w table
  for n in 1 2 3; do echo "etcd$n: $(ctl "$n" get /config/modo --print-value-only)"; done
} 2>&1 | tee "$SAIDA"

echo; echo "Evidencia salva em $SAIDA"
