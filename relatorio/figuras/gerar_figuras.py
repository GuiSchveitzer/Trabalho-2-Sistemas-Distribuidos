# Gera as figuras do relatorio que dependem dos resultados dos experimentos, com os papeis e
# valores das evidencias em evidencias/:
#   fig1_arquitetura.png        topologia com o lider observado no E1 (etcd1, termo 2)
#   fig3_sequencia_escrita.png  caminho do put do E2 (seguidor etcd2 -> lider etcd1)
#   fig4_timeline_enfase_b.png  cenarios 1 e 2 do E9 com os tokens de e9_cenario1/2.txt
# A fig2_estados_raft.png nao depende dos experimentos e nao e gerada aqui.
# Requer matplotlib. Uso: python relatorio/figuras/gerar_figuras.py
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch, Rectangle

PASTA = Path(__file__).parent
DPI = 200

AZUL, AZUL_FUNDO = "#1f4e79", "#dce9f5"
LARANJA, LARANJA_FUNDO = "#c55a11", "#fbe5d6"
VERDE, VERDE_FUNDO, VERDE_REGIAO = "#2e7d32", "#e3f0e3", "#f5faf5"
CINZA, CINZA_FUNDO = "#595959", "#eeeeee"
VERMELHO = "#b71c1c"
AMARELO, AMARELO_FUNDO = "#bf9000", "#fff2cc"


def tela(largura, altura):
    # Eixos em pixels (origem no canto superior esquerdo), do mesmo tamanho das figuras originais
    fig = plt.figure(figsize=(largura / DPI, altura / DPI), dpi=DPI)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, largura)
    ax.set_ylim(altura, 0)
    ax.axis("off")
    return fig, ax


def caixa(ax, x, y, l, a, texto="", borda=AZUL, fundo=AZUL_FUNDO, tam=8.8, peso="normal", tracejada=False, raio=12):
    ax.add_patch(FancyBboxPatch((x, y), l, a, boxstyle=f"round,pad=0,rounding_size={raio}",
                                linewidth=2.2, edgecolor=borda, facecolor=fundo,
                                linestyle="--" if tracejada else "-"))
    if texto:
        ax.text(x + l / 2, y + a / 2, texto, ha="center", va="center", fontsize=tam, fontweight=peso,
                linespacing=1.25)


def seta(ax, de, para, cor, dupla=False, curva=0.0, lw=2.2):
    ax.annotate("", xy=para, xytext=de,
                arrowprops=dict(arrowstyle="<|-|>" if dupla else "-|>", color=cor, lw=lw,
                                mutation_scale=18, shrinkA=0, shrinkB=0,
                                connectionstyle=f"arc3,rad={curva}"))


def figura_topologia():
    fig, ax = tela(1589, 994)
    # Redes
    caixa(ax, 48, 47, 1494, 337, borda=LARANJA, fundo="#fff7f2", tracejada=True)
    ax.text(82, 82, "Rede interna 172.30.0.0/24  —  tráfego Raft entre pares (porta 2380)",
            color=LARANJA, fontsize=8.8, fontweight="bold", va="center")
    caixa(ax, 48, 578, 1494, 368, borda=VERDE, fundo=VERDE_REGIAO, tracejada=True)
    ax.text(82, 908, "Rede clientes 172.31.0.0/24  —  API gRPC/HTTP do etcd (porta 2379) e ênfase B (porta 8000)",
            color=VERDE, fontsize=8.8, fontweight="bold", va="center")

    # Membros: lider observado no E1 (etcd1, termo 2)
    caixa(ax, 172, 263, 316, 290, "etcd1\nLÍDER (termo 2 no E1)\n\n.31 interna | .31 clientes\nlog Raft + MVCC (bbolt)",
          borda=LARANJA, fundo=LARANJA_FUNDO)
    caixa(ax, 637, 263, 316, 290, "etcd2\nseguidor\n\n.32 interna | .32 clientes\nlog Raft + MVCC (bbolt)")
    caixa(ax, 1102, 263, 316, 290, "etcd3\nseguidor\n\n.33 interna | .33 clientes\nlog Raft + MVCC (bbolt)")
    seta(ax, (488, 350), (635, 350), LARANJA)
    seta(ax, (488, 316), (1100, 316), LARANJA, curva=-0.25)
    ax.text(795, 211, "AppendEntries / heartbeat (100 ms)", color=LARANJA, fontsize=8.4, ha="center", va="center",
            bbox=dict(facecolor="white", edgecolor="none", pad=1))

    # Clientes: worker1 usa o etcd1 e worker2 o etcd2 (scripts/e9_trava_fencing.sh)
    caixa(ax, 125, 655, 278, 206, "worker1\n.101", borda=VERDE, fundo=VERDE_FUNDO)
    caixa(ax, 513, 655, 277, 206, "recurso\n.50 :8000\ncontador protegido", borda=VERDE, fundo=VERDE_FUNDO)
    caixa(ax, 900, 655, 278, 206, "worker2\n.102", borda=VERDE, fundo=VERDE_FUNDO)
    caixa(ax, 1210, 655, 278, 206, "cliente\n.100\nPython + etcdctl\n(medições)", borda=VERDE, fundo=VERDE_FUNDO)
    seta(ax, (268, 557), (268, 651), VERDE, dupla=True)
    seta(ax, (900, 557), (1000, 651), VERDE, dupla=True)
    seta(ax, (1310, 557), (1349, 651), VERDE, dupla=True)
    ax.text(585, 603, "lock / lease / keepalive", color=VERDE, fontsize=8, ha="center", va="center")
    ax.text(1295, 603, "endpoint único de cada membro", color=VERDE, fontsize=7.2, ha="right", va="center")
    seta(ax, (407, 758), (509, 758), VERDE, dupla=True)
    seta(ax, (794, 758), (896, 758), VERDE, dupla=True)
    ax.text(458, 706, "ler/escrever\n+ token", color=VERDE, fontsize=7.6, ha="center", va="center")
    ax.text(845, 706, "ler/escrever\n+ token", color=VERDE, fontsize=7.6, ha="center", va="center")
    fig.savefig(PASTA / "fig1_arquitetura.png", dpi=DPI, facecolor="white")
    plt.close(fig)


def figura_sequencia():
    fig, ax = tela(1589, 964)
    # Participantes do E2: put enviado ao seguidor etcd2; lider etcd1; outro seguidor etcd3
    xs = {"cliente": 160, "etcd2": 501, "etcd1": 873, "etcd3": 1245}
    caixa(ax, 41, 33, 238, 113, "Cliente\n(etcdctl)", tam=9.2)
    caixa(ax, 382, 33, 238, 113, "etcd2\nseguidor", tam=9.2)
    caixa(ax, 754, 33, 238, 113, "etcd1\nLÍDER", borda=LARANJA, fundo=LARANJA_FUNDO, tam=9.2)
    caixa(ax, 1126, 33, 238, 113, "etcd3\nseguidor", tam=9.2)
    for x in xs.values():
        ax.plot([x, x], [150, 915], color=CINZA, lw=1.6, linestyle=(0, (1, 2)))

    def msg(y, de, para, texto, cor, xt=None):
        seta(ax, (xs[de] + (4 if xs[para] > xs[de] else -4), y), (xs[para] + (-6 if xs[para] > xs[de] else 6), y), cor)
        ax.text(xt if xt is not None else (xs[de] + xs[para]) / 2, y - 33, texto, color=cor, fontsize=8.8,
                ha="center", va="center")

    msg(205, "cliente", "etcd2", "1. Put(/config/modo) — gRPC :2379", AZUL, xt=330)
    msg(282, "etcd2", "etcd1", "2. MsgProp: seguidor repassa a proposta ao líder", AZUL)
    msg(397, "etcd1", "etcd2", "", LARANJA)
    msg(397, "etcd1", "etcd3", "", LARANJA)
    ax.text(686, 364, "3. AppendEntries(termo, índice, entrada)", color=LARANJA, fontsize=8.8, ha="center", va="center")
    msg(505, "etcd2", "etcd1", "", VERDE)
    msg(505, "etcd3", "etcd1", "", VERDE)
    ax.text(686, 472, "4. ack (gravou no WAL + fsync)", color=VERDE, fontsize=8.8, ha="center", va="center")
    caixa(ax, 730, 548, 285, 83, "5. maioria (2 de 3) → COMMIT\naplica na máquina de estados",
          borda=AMARELO, fundo=AMARELO_FUNDO, tam=8.4, raio=3)
    ax.text(1383, 571, "basta 1 ack além\ndo próprio líder", color=CINZA, fontsize=8, ha="center", va="center")
    msg(697, "etcd1", "etcd2", "", LARANJA)
    msg(697, "etcd1", "etcd3", "", LARANJA)
    ax.text(686, 664, "6. próximo AppendEntries leva o commitIndex", color=LARANJA, fontsize=8.8, ha="center",
            va="center")
    msg(821, "etcd2", "cliente", "7. resposta {revision 2, raft_term 2} do etcd2", AZUL, xt=330)
    fig.savefig(PASTA / "fig3_sequencia_escrita.png", dpi=DPI, facecolor="white")
    plt.close(fig)


def painel_enfase_b(ax, y0, titulo, cor_titulo, token_w1, tokens_w2, resultado, cor_resultado, cor_seta):
    ax.text(36, y0 + 40, titulo, color=cor_titulo, fontsize=10.5, fontweight="bold", va="center")
    linhas = {"worker1": y0 + 163, "etcd (trava)": y0 + 308, "worker2": y0 + 453, "recurso": y0 + 583}
    for nome, y in linhas.items():
        ax.text(36, y, nome, fontsize=9.2, fontweight="bold", va="center")
        ax.plot([270, 1950], [y, y], color="#d9d9d9", lw=2, zorder=0)
    x_expira, x_unpause = 875, 1479

    # worker1: trava obtida e congelado (docker pause) dentro da secao critica
    ax.add_patch(Rectangle((271, y0 + 135), 100, 57, facecolor=AZUL_FUNDO, edgecolor=AZUL, lw=2))
    ax.add_patch(Rectangle((371, y0 + 135), x_unpause - 371, 57, facecolor=CINZA_FUNDO, edgecolor=CINZA, lw=2,
                           hatch="//"))
    ax.text(925, y0 + 163, "docker pause (congelado com a trava 'na mão')", fontsize=8.8, ha="center", va="center")
    ax.text(321, y0 + 96, f"trava\ntoken {token_w1}", fontsize=7.6, ha="center", va="center")
    ax.text(1772, y0 + 171, "worker1 só percebe\nque perdeu o lease\nDEPOIS de escrever", color=CINZA, fontsize=7.6,
            ha="center", va="center")

    # etcd: lease de worker1 vence ~5 s apos a ultima renovacao; a trava passa a worker2
    ax.add_patch(Rectangle((271, y0 + 280), x_expira - 271, 57, facecolor=AZUL_FUNDO, edgecolor=AZUL, lw=2))
    ax.text(573, y0 + 308, "lease de worker1 (TTL 5 s, sem keepalive)", fontsize=8.4, ha="center", va="center")
    ax.add_patch(Rectangle((883, y0 + 280), 1470 - 883, 57, facecolor=VERDE_FUNDO, edgecolor=VERDE, lw=2))
    ax.text(1176, y0 + 308, "trava de worker2", fontsize=8.4, ha="center", va="center")

    # worker2: tres incrementos com tokens crescentes
    ax.text(1076, y0 + 396, "tokens " + ", ".join(map(str, tokens_w2)), color=VERDE, fontsize=8, ha="center",
            va="center")
    for i, x in enumerate((892, 1076, 1260)):
        ax.add_patch(Rectangle((x, y0 + 425), 159, 57, facecolor=VERDE_FUNDO, edgecolor=VERDE, lw=2))
        ax.text(x + 79, y0 + 453, "+1", fontsize=8.8, ha="center", va="center")
        seta(ax, (x + 150, y0 + 486), (x + 150, y0 + 560), VERDE)
        ax.text(x + 79, y0 + 613, f"{i}→{i + 1}", color=VERDE, fontsize=8, ha="center", va="center")

    ax.plot([x_expira, x_expira], [y0 + 125, y0 + 612], color=VERMELHO, lw=2, linestyle="--")
    ax.text(x_expira, y0 + 78, "lease expira", color=VERMELHO, fontsize=8, ha="center", va="center")
    ax.plot([x_unpause, x_unpause], [y0 + 120, y0 + 612], color=CINZA, lw=2, linestyle=(0, (1, 2)))
    ax.text(x_unpause, y0 + 78, "unpause", color=CINZA, fontsize=8, ha="center", va="center")

    # Escrita atrasada de worker1 chega ao recurso
    seta(ax, (1513, y0 + 196), (1596, y0 + 560), cor_seta, lw=2.5)
    ax.text(1820, y0 + 520, resultado, color=cor_resultado, fontsize=9.2, fontweight="bold", ha="center",
            va="center")


def figura_enfase_b():
    # Tokens dos cenarios 1 e 2 em evidencias/e9_cenario1.txt e e9_cenario2.txt
    fig, ax = tela(2079, 1336)
    painel_enfase_b(ax, 0, "(a) SEM fencing — violação da exclusão mútua", VERMELHO,
                    25174, (25175, 25178, 25180), "aceita: 3 → 1\natualizações perdidas!", VERMELHO, VERMELHO)
    painel_enfase_b(ax, 638, "(b) COM fencing token — escrita atrasada rejeitada", VERDE,
                    25182, (25183, 25186, 25188), "REJEITADA (409)\n25182 < 25188", VERDE, CINZA)
    fig.savefig(PASTA / "fig4_timeline_enfase_b.png", dpi=DPI, facecolor="white")
    plt.close(fig)


if __name__ == "__main__":
    figura_topologia()
    figura_sequencia()
    figura_enfase_b()
    print("figuras geradas em", PASTA)
