# Enfase B - Worker que incrementa o contador do recurso dentro de uma trava do etcd.
# A trava usa um lease com TTL; uma thread renova o lease (keepalive) enquanto o worker vive.
# Se o worker for congelado (docker pause) por mais que o TTL, o lease vence, a trava e
# liberada para outro worker, mas este aqui "nao sabe" e escreve ao acordar.
#
# Uso: python worker.py <nome> <ip_etcd> [--ttl 5] [--iteracoes 1] [--trabalho 1.0]
import argparse
import base64
import json
import threading
import time
import urllib.error
import urllib.request

RECURSO = "http://172.31.0.50:8000"
trava_log = threading.Lock()  # a thread de keepalive e a principal podem logar no mesmo instante


def log(nome, msg):
    agora = time.time()
    linha = f"{time.strftime('%H:%M:%S', time.localtime(agora))}.{int(agora * 1000) % 1000:03d} [{nome}] {msg}"
    with trava_log:
        print(linha, flush=True)


def http(url, corpo=None, timeout=10):
    dados = json.dumps(corpo).encode() if corpo is not None else None
    req = urllib.request.Request(url, data=dados, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, json.loads(resp.read())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")


def renovar_lease(nome, etcd, lease, ttl, parar):
    # Renova o lease a cada ttl/3 s; se o etcd responder sem TTL, o lease ja expirou
    ultima = time.time()  # instante da ultima renovacao bem-sucedida (ou da concessao)
    while not parar.wait(ttl / 3):
        _, resp = http(f"{etcd}/v3/lease/keepalive", {"ID": lease})
        if "TTL" not in resp.get("result", {}):
            log(nome, f"keepalive: lease {lease} NAO existe mais (expirou) -> a trava ja nao e minha! "
                      f"ultima_renovacao_ms={int(ultima * 1000)}")
            return
        ultima = time.time()


def uma_iteracao(nome, etcd, ttl, trabalho):
    _, resp = http(f"{etcd}/v3/lease/grant", {"TTL": ttl})
    lease = resp["ID"]
    parar = threading.Event()
    threading.Thread(target=renovar_lease, args=(nome, etcd, lease, ttl, parar), daemon=True).start()

    log(nome, f"aguardando trava (lease {lease}, TTL {ttl}s)...")
    nome_trava = base64.b64encode(b"trava").decode()
    _, resp = http(f"{etcd}/v3/lock/lock", {"name": nome_trava, "lease": lease}, timeout=None)
    chave = resp["key"]

    # Fencing token = create_revision da chave da trava (revisao global, sempre crescente)
    _, kv = http(f"{etcd}/v3/kv/range", {"key": chave})
    token = int(kv["kvs"][0]["create_revision"])
    log(nome, f"TRAVA obtida  token={token}  chave={base64.b64decode(chave).decode()}  t_ms={int(time.time() * 1000)}")

    # Secao critica: leitura -> processamento -> escrita
    _, r = http(f"{RECURSO}/ler")
    valor = r["valor"]
    log(nome, f"li valor={valor}; processando por {trabalho}s...")
    time.sleep(trabalho)
    codigo, _ = http(f"{RECURSO}/escrever", {"worker": nome, "valor": valor + 1, "token": token})
    if codigo == 200:
        log(nome, f"escrevi valor={valor + 1} com token={token}: ACEITA")
    else:
        log(nome, f"escrevi valor={valor + 1} com token={token}: REJEITADA pelo recurso (HTTP {codigo})")

    http(f"{etcd}/v3/lock/unlock", {"key": chave})
    parar.set()
    http(f"{etcd}/v3/lease/revoke", {"ID": lease})
    log(nome, "trava liberada")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("nome")
    p.add_argument("ip_etcd")
    p.add_argument("--ttl", type=int, default=5)
    p.add_argument("--iteracoes", type=int, default=1)
    p.add_argument("--trabalho", type=float, default=1.0)
    a = p.parse_args()

    for _ in range(a.iteracoes):
        uma_iteracao(a.nome, f"http://{a.ip_etcd}:2379", a.ttl, a.trabalho)
