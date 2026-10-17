#!/usr/bin/env bash
# Recria o ambiente do zero e executa todos os experimentos em sequencia (E1 a E9).
# Leva cerca de 20 minutos. Nao mexa nos conteineres enquanto roda.
# Uso: bash scripts/executar_todos.sh
source "$(dirname "$0")/comum.sh"
cd "$RAIZ"

echo "=== $(date '+%Y-%m-%d %H:%M:%S') recriando o ambiente do zero ==="
docker compose down
docker compose up -d --build
espera_saudavel || exit 1
sleep 3

for s in e1_topologia e2_caminho e3_replicacao e4_consistencia e5_falha_quorum e6_particao \
         e7_recuperacao e7b_snapshot e8_coordenacao e9_trava_fencing; do
  inicio=$(date +%s)
  echo "=== $(date '+%H:%M:%S') $s ==="
  # cada script ja grava a propria evidencia em evidencias/; aqui so mostramos o codigo de saida
  timeout 900 bash "scripts/$s.sh" > /dev/null 2>&1
  echo "    terminou com codigo $? em $(( $(date +%s) - inicio )) s"
  espera_saudavel; sleep 2
done
echo "=== $(date '+%H:%M:%S') fim; evidencias em $EVID ==="
