# Ferramenta de apoio aos experimentos: fala com o etcd pela API HTTP/JSON (gateway gRPC).
# Roda dentro de um contêiner da rede de clientes, evitando o custo do "docker exec" nas medicoes.
#
# Uso:
#   python etcd_http.py metricas <ip> [filtro]           -> linhas de /metrics que contem o filtro
#   python etcd_http.py carga <ip> <n> <bytes>           -> n puts de <bytes> bytes no membro <ip>
#   python etcd_http.py latencia <ip> <n> [s]            -> latencia media (ms) de put e get; "s" = get serializavel
#   python etcd_http.py propagacao <ip_put> <ip_get> <n> -> tempo (ms) ate o valor escrito em um membro aparecer em outro
#   python etcd_http.py eleicao <ip_lider> <ip_s1> <ip_s2> -> tempo (ms) entre a queda do lider e um novo lider
#   python etcd_http.py alcanca <ip_membro> <ip_ref>      -> tempo (ms) ate o membro alcancar o indice Raft da referencia
import base64
import json
import sys
import time
import urllib.request


def b64(texto):
    return base64.b64encode(texto.encode()).decode()


def chamar(ip, caminho, corpo):
    req = urllib.request.Request(f"http://{ip}:2379{caminho}", data=json.dumps(corpo).encode(),
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read())


def put(ip, chave, valor):
    return chamar(ip, "/v3/kv/put", {"key": b64(chave), "value": b64(valor)})


def get(ip, chave, serializavel=False):
    resp = chamar(ip, "/v3/kv/range", {"key": b64(chave), "serializable": serializavel})
    if "kvs" not in resp:
        return None
    return base64.b64decode(resp["kvs"][0]["value"]).decode()


def metricas(ip, filtro=""):
    with urllib.request.urlopen(f"http://{ip}:2379/metrics", timeout=10) as resp:
        for linha in resp.read().decode().splitlines():
            if not linha.startswith("#") and filtro in linha:
                print(linha)


def carga(ip, n, tamanho):
    valor = "x" * tamanho
    inicio = time.time()
    for i in range(n):
        put(ip, f"/carga/{i}", valor)
    print(f"{n} puts de {tamanho} bytes em {ip}: {time.time() - inicio:.2f} s")


def latencia(ip, n, serializavel=False):
    t_put, t_get = [], []
    for i in range(n):
        t0 = time.perf_counter()
        put(ip, "/latencia", str(i))
        t1 = time.perf_counter()
        get(ip, "/latencia", serializavel)
        t2 = time.perf_counter()
        t_put.append((t1 - t0) * 1000)
        t_get.append((t2 - t1) * 1000)
    # Saida em uma linha para os scripts .sh coletarem com awk
    print(f"put_ms={sum(t_put) / n:.2f} get_ms={sum(t_get) / n:.2f}")


def status(ip, timeout=0.05):
    req = urllib.request.Request(f"http://{ip}:2379/v3/maintenance/status", data=b"{}")
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read())


def eleicao(ip_lider, sobreviventes):
    # Mede do instante em que o lider antigo para de responder ate um sobrevivente
    # reconhecer um lider NOVO. Fica pronto antes do "docker kill" ser executado no host.
    antigo = status(ip_lider, 2)
    print(f"pronto: lider antigo {antigo['leader']} termo {antigo['raftTerm']}", flush=True)
    while True:
        try:
            status(ip_lider)
            time.sleep(0.01)
        except Exception:
            t0 = time.perf_counter()
            break
    while True:
        for ip in sobreviventes:
            try:
                s = status(ip)
            except Exception:
                continue
            if s.get("leader", "0") not in ("0", antigo["leader"]):
                ms = (time.perf_counter() - t0) * 1000
                # o status le lider e termo em momentos diferentes; relê o termo depois de estabilizar
                time.sleep(0.3)
                s = status(ip, 1)
                print(f"eleicao_ms={ms:.0f} novo_lider={s['leader']} "
                      f"termo={s['raftTerm']} (antes {antigo['raftTerm']})", flush=True)
                return
        time.sleep(0.01)


def estado_membro(ip):
    try:
        s = status(ip, 0.2)
        return int(s["raftTerm"]), int(s["raftAppliedIndex"])
    except Exception:
        return None


def alcanca(ip_membro, ip_ref):
    # Espera o membro aplicar todas as entradas que a referencia ja tinha e imprime o instante
    # (epoch em ms, relogio dos conteineres) para o script subtrair do instante da reconexao.
    alvo = int(status(ip_ref, 2)["raftIndex"])
    inicial = None
    while inicial is None:  # membro recem-iniciado pode ainda nao responder
        inicial = estado_membro(ip_membro)
        time.sleep(0.01)
    print(f"pronto: indice alvo {alvo}; membro em termo {inicial[0]}, indice {inicial[1]}", flush=True)
    while True:
        atual = estado_membro(ip_membro)
        if atual and atual[1] >= alvo:
            break
        time.sleep(0.005)
    print(f"t_fim_ms={int(time.time() * 1000)} entradas={alvo - inicial[1]} "
          f"termo {inicial[0]} -> {atual[0]}", flush=True)


def propagacao(ip_put, ip_get, n):
    for i in range(n):
        valor = f"v{time.time_ns()}"
        t0 = time.perf_counter()
        put(ip_put, "/propagacao", valor)
        # Leitura serializavel = estado local do membro, sem passar pelo lider
        while get(ip_get, "/propagacao", serializavel=True) != valor:
            pass
        print(f"{(time.perf_counter() - t0) * 1000:.2f}")
        time.sleep(0.2)


if __name__ == "__main__":
    cmd, args = sys.argv[1], sys.argv[2:]
    if cmd == "metricas":
        metricas(args[0], args[1] if len(args) > 1 else "")
    elif cmd == "carga":
        carga(args[0], int(args[1]), int(args[2]))
    elif cmd == "latencia":
        latencia(args[0], int(args[1]), len(args) > 2 and args[2] == "s")
    elif cmd == "propagacao":
        propagacao(args[0], args[1], int(args[2]))
    elif cmd == "eleicao":
        eleicao(args[0], args[1:])
    elif cmd == "alcanca":
        alcanca(args[0], args[1])
    else:
        print(__doc__ or "comando desconhecido")
