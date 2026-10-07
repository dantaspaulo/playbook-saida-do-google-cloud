#!/usr/bin/env python3
"""Gera as imagens animadas do README (usa docs/cartoes.py, o gerador da skill perfil-github).

Uso: python3 docs/gerar_docs.py
"""
import importlib.util
import tempfile
from pathlib import Path

AQUI = Path(__file__).resolve().parent
SAIDA = AQUI / "assets"
spec = importlib.util.spec_from_file_location("cartoes", AQUI / "cartoes.py")
cartoes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cartoes)

BASE = {"login": "playbook-gcp-para-vps", "nome": "playbook", "tema": "champagne", "contatos": {"site": "https://x"}}

BLOCOS = {
    # nome final: (bloco gerado, config)
    "numeros": ("numeros", {"numeros": [
        {"valor": "−95%", "rotulo": ["no custo mensal", "de nuvem"], "fonte": "faturamento"},
        {"valor": "14 min", "rotulo": ["fora do ar no corte,", "de madrugada"], "fonte": "log do corte"},
        {"valor": "6 dias", "rotulo": ["do plano às VMs", "do Google apagadas"], "fonte": "linha do tempo"},
        {"valor": "11 → 1", "rotulo": ["máquinas virtuais", "viraram uma VPS"], "fonte": "inventário"},
    ]}),
    "antes-depois": ("cases", {"cases": [
        {"icone": "☁️", "nome": "Antes", "sub": "Google Cloud gerenciado", "selo": "SETEMBRO",
         "numero": "R$ 6,7 mil", "rotulo": ["por mês: ~11 VMs, banco", "gerenciado e balanceador"],
         "rodape": "VMs ~3/4 da conta · banco gerenciado ~1/4"},
        {"icone": "🖥️", "nome": "Depois", "sub": "uma VPS com Docker Swarm", "selo": "OUTUBRO",
         "numero": "~R$ 320", "rotulo": ["por mês, já contando a VPS", "no preço de renovação"],
         "rodape": "8 vCPU · 32 GB de RAM · 400 GB NVMe"},
    ]}),
    "deu-errado": ("cases", {"cases": [
        {"icone": "🔌", "nome": "O túnel caiu", "sub": "cópia grande pela VPN", "selo": "REDE",
         "numero": "13 → 60", "rotulo": ["MB/s depois de trocar a VPN", "por SSH sobre TCP"],
         "rodape": "o UDP parou com uns 4 GB copiados"},
        {"icone": "🔁", "nome": "Deploy com erro", "sub": "o servidor fechava no SIGTERM", "selo": "DEPLOY",
         "numero": "78 → 0", "rotulo": ["erros por deploy, com dreno", "de 20 s e duas réplicas"],
         "rodape": "o proxy leva segundos para soltar a réplica"},
        {"icone": "🔤", "nome": "Uma letra", "sub": "websocket atrás da Cloudflare", "selo": "CLOUDFLARE",
         "numero": "ã", "rotulo": ["de \"São Paulo\" num cabeçalho", "derrubava o tempo real"],
         "rodape": "cabeçalho de localização apagado na borda"},
        {"icone": "💳", "nome": "IP não liberado", "sub": "gateway de pagamento", "selo": "INTEGRAÇÃO",
         "numero": "403", "rotulo": ["na conferência antes do corte:", "chave restrita por IP"],
         "rodape": "o roteiro recusou seguir até liberar"},
    ]}),
    "metodo": ("metodo", {"metodo": {"passos": [
        {"nome": "Medir", "sub": ["custo por serviço", "e uso real"]},
        {"nome": "Ensaiar", "sub": ["cópia e contagem", "sem desligar nada"]},
        {"nome": "Cortar", "sub": ["um passo por vez,", "com volta pronta"]},
        {"nome": "Vigiar", "sub": ["de fora da VPS,", "a cada 5 minutos"]},
        {"nome": "Desligar", "sub": ["parar primeiro,", "apagar dias depois"]},
    ]}}),
    "principios": ("principios", {"principios": {"itens": [
        {"icone": "🗑️", "linhas": ["Apagar só", "dias depois"]},
        {"icone": "💾", "linhas": ["Backup só vale", "restaurado"]},
        {"icone": "👣", "linhas": ["Um passo", "por vez"]},
        {"icone": "↩️", "linhas": ["Volta atrás", "escrita antes"]},
        {"icone": "🔭", "linhas": ["Vigia do", "lado de fora"]},
    ]}}),
}


def main():
    SAIDA.mkdir(parents=True, exist_ok=True)
    for velho in SAIDA.glob("*.svg"):
        velho.unlink()
    problemas = []
    for final, (bloco, cfg) in BLOCOS.items():
        cfg = {**BASE, **cfg}
        with tempfile.TemporaryDirectory() as tmp:
            repo = Path(tmp) / BASE["login"]
            cartoes.gerar_svgs(cfg, repo / "assets")
            erros, _ = cartoes.conferir(cfg, repo, [])
            problemas += [f"{final}: {e}" for e in erros]
            for sufixo in ("", "-celular"):
                origem = repo / "assets" / f"{bloco}{sufixo}.svg"
                (SAIDA / f"{final}{sufixo}.svg").write_text(origem.read_text(encoding="utf-8"), encoding="utf-8")
    for p in problemas:
        print("ERRO:", p)
    print("ok:", ", ".join(sorted(p.name for p in SAIDA.glob("*.svg"))))
    raise SystemExit(1 if problemas else 0)


if __name__ == "__main__":
    main()
