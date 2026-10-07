#!/usr/bin/env python3
"""Lê o CSV de faturamento da nuvem e mostra onde o dinheiro vai.

Uso: python3 ler_custo.py relatorio.csv [--top 15]

Feito para o CSV de Billing → Reports do Google Cloud (agrupado por serviço e
SKU), mas tenta reconhecer as colunas de outros relatórios: procura uma coluna
de serviço, uma de SKU (opcional) e uma de custo, em português ou inglês.
"""
import argparse
import csv
import re
import sys
from collections import defaultdict


def numero(txt):
    t = (txt or "").strip().replace("R$", "").replace("US$", "").replace("$", "").replace(" ", "").strip()
    if not t or t in "-–":
        return 0.0
    neg = t.startswith("(") and t.endswith(")")
    t = t.strip("()")
    if "," in t and "." in t:
        t = t.replace(".", "").replace(",", ".") if t.rfind(",") > t.rfind(".") else t.replace(",", "")
    elif "," in t:
        t = t.replace(",", ".")
    try:
        v = float(re.sub(r"[^0-9.\-]", "", t))
    except ValueError:
        return 0.0
    return -v if neg else v


def achar(cab, *padroes, evitar=()):
    for p in padroes:
        for i, c in enumerate(cab):
            n = c.lower()
            if re.search(p, n) and not any(e in n for e in evitar):
                return i
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--top", type=int, default=15)
    a = ap.parse_args()

    with open(a.csv, encoding="utf-8-sig", newline="") as f:
        amostra = f.read(4096)
        f.seek(0)
        dialeto = csv.Sniffer().sniff(amostra, delimiters=",;\t")
        linhas = list(csv.reader(f, dialeto))
    # alguns relatórios têm linhas de título antes do cabeçalho
    ini = next((i for i, l in enumerate(linhas) if any(re.search(r"servi|service", c.lower()) for c in l)), None)
    if ini is None:
        sys.exit("não achei a coluna de serviço; exporte o relatório agrupado por serviço (e SKU)")
    cab, dados = linhas[ini], linhas[ini + 1:]
    i_serv = achar(cab, r"service desc", r"descri.*servi", r"^servi", r"service")
    i_sku = achar(cab, r"sku desc", r"descri.*sku", r"^sku$")
    i_custo = achar(cab, r"^subtotal", r"^cost \(", r"^custo \(", r"^cost$", r"^custo$", r"cost", r"custo",
                    evitar=("type", "tipo", "unrounded", "não arred", "nao arred", "savings", "economia", "discount", "desconto", "credit", "crédito"))
    if i_custo is None:
        sys.exit("não achei a coluna de custo")

    por_serv, por_sku = defaultdict(float), defaultdict(float)
    for l in dados:
        if len(l) <= max(i for i in (i_serv, i_sku, i_custo) if i is not None):
            continue
        serv = l[i_serv].strip() or "(sem serviço)"
        if serv.lower().startswith(("total", "subtotal")):
            continue
        v = numero(l[i_custo])
        por_serv[serv] += v
        if i_sku is not None:
            por_sku[(serv, l[i_sku].strip())] += v

    total = sum(por_serv.values())
    print(f"Coluna de custo usada: '{cab[i_custo]}'. Total: {total:,.2f}\n")
    print("Por serviço:")
    for s, v in sorted(por_serv.items(), key=lambda x: -x[1])[: a.top]:
        print(f"  {v:>12,.2f}  {v / total:>6.1%}  {s}" if total else f"  {v:>12,.2f}  {s}")
    if por_sku:
        print("\nSKUs que mais pesam:")
        for (s, k), v in sorted(por_sku.items(), key=lambda x: -x[1])[: a.top]:
            print(f"  {v:>12,.2f}  {v / total:>6.1%}  {s} · {k}" if total else f"  {v:>12,.2f}  {s} · {k}")
    print("\nPerguntas para cada linha do topo: isso está em uso? quanto do contratado é usado? existe")
    print("alternativa sem estado gerenciado? Disco, snapshot e IP sem dono costumam ser corte imediato.")


if __name__ == "__main__":
    main()
