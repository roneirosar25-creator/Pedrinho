#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
QA_CONSOLIDA_DADOS — TRIVIUM369
================================

Passos 2 e 3 do pipeline: VALIDAR (QA) e CONSOLIDAR os CSVs brutos
gerados pelo script COLETA_HISTORICO_TRIVIUM (MT5 / Admirals).

Filosofia: lixo entra, lixo sai. Antes de qualquer backtest ou estratégia,
os dados precisam estar limpos e auditados.

O que ele faz
-------------
1. Encontra todos os CSVs no padrao  <TF>_<ATIVO>-T.csv  dentro das pastas
   DADOS_BRUTOS_* (ex: DADOS_BRUTOS_EURUSD/M1_EURUSD-T.csv).
2. Para cada arquivo audita:
   - colunas e cabecalho corretos
   - linhas que nao parseiam (data/hora ou numeros invalidos)
   - candles duplicados (mesmo timestamp)
   - candles fora de ordem cronologica
   - OHLC invalido (high<low, high<max(o,c), low>min(o,c), zero/negativo, NaN)
   - volume negativo
   - buracos (gaps) suspeitos na serie, ignorando fins de semana
3. Gera versao LIMPA de cada arquivo (ordenada, sem duplicatas, validada),
   com uma coluna ISO 'datetime' pronta pra analise.
4. Escreve um relatorio de saude:  RELATORIO_QA.md  +  qa_resumo.csv

Dependencias: NENHUMA (apenas biblioteca padrao do Python 3.8+).

Uso
---
    python qa_consolida_dados.py                 # usa a pasta atual
    python qa_consolida_dados.py --input "C:\\caminho\\com\\DADOS_BRUTOS_..."
    python qa_consolida_dados.py --input . --output DADOS_LIMPOS

Saida (exit code): 0 se nenhum arquivo deu FALHA, 1 caso contrario.
"""

from __future__ import annotations

import argparse
import csv
import math
import os
import sys
from datetime import datetime, timedelta

# ----------------------------------------------------------------------------
# Configuracao de timeframes
# ----------------------------------------------------------------------------
TFS_VALIDOS = {
    "M1": 1, "M2": 2, "M5": 5, "M15": 15,
    "H1": 60, "H4": 240, "D1": 1440,
}

COLUNAS_ESPERADAS = ["date", "time", "open", "high", "low", "close", "volume"]

# limite de linhas ruins (parse/OHLC) acima do qual o arquivo vira FALHA
LIMITE_FALHA_PCT = 5.0


# ----------------------------------------------------------------------------
# Descoberta de arquivos
# ----------------------------------------------------------------------------
def descobrir_csvs(raiz):
    """Retorna lista de (caminho, ativo_com_T, timeframe) achados sob 'raiz'."""
    achados = []
    for dirpath, _dirs, arquivos in os.walk(raiz):
        for nome in arquivos:
            if not nome.lower().endswith(".csv"):
                continue
            base = nome[:-4]  # tira .csv
            if "_" not in base:
                continue
            tf, _, resto = base.partition("_")
            tf = tf.upper()
            if tf not in TFS_VALIDOS or not resto:
                continue
            ativo = resto  # ex: EURUSD-T
            achados.append((os.path.join(dirpath, nome), ativo, tf))
    achados.sort(key=lambda x: (x[1], list(TFS_VALIDOS).index(x[2])))
    return achados


# ----------------------------------------------------------------------------
# Parsing de uma linha
# ----------------------------------------------------------------------------
def _num_ok(x):
    return not (math.isnan(x) or math.isinf(x))


def parse_linha(row):
    """Converte uma linha do CSV. Retorna (dt, o, h, l, c, v) ou levanta ValueError."""
    dt = datetime.strptime(row["date"].strip() + " " + row["time"].strip(),
                           "%Y.%m.%d %H:%M")
    o = float(row["open"]); h = float(row["high"])
    lo = float(row["low"]); c = float(row["close"])
    v = int(float(row["volume"]))
    for val in (o, h, lo, c):
        if not _num_ok(val):
            raise ValueError("OHLC nao numerico")
    return dt, o, h, lo, c, v


def ohlc_invalido(o, h, lo, c):
    """True se o candle viola regras basicas de OHLC."""
    if min(o, h, lo, c) <= 0:
        return True
    if h < lo:
        return True
    if h < max(o, c) - 1e-12:
        return True
    if lo > min(o, c) + 1e-12:
        return True
    return False


# ----------------------------------------------------------------------------
# Deteccao de gaps (heuristica, ignora fim de semana)
# ----------------------------------------------------------------------------
def _cobre_fim_de_semana(t0, t1):
    """True se existe um sabado ou domingo no intervalo (t0, t1]."""
    d = t0.date()
    fim = t1.date()
    passos = 0
    while d <= fim and passos < 40:
        if d.weekday() >= 5:  # 5=sab, 6=dom
            return True
        d = d + timedelta(days=1)
        passos += 1
    return False


def contar_gaps(timestamps, tf):
    """
    Conta gaps 'suspeitos' (buracos na serie que NAO sao fim de semana).
    Retorna (n_suspeitos, maior_gap_min, par_do_maior_gap).
    Heuristica: feriados podem aparecer como suspeitos — por isso e' so AVISO.
    """
    esperado = TFS_VALIDOS[tf]
    suspeitos = 0
    maior = 0.0
    maior_par = None
    for i in range(1, len(timestamps)):
        t0 = timestamps[i - 1]
        t1 = timestamps[i]
        diff_min = (t1 - t0).total_seconds() / 60.0
        if diff_min <= esperado * 1.5:
            continue  # dentro do esperado
        if _cobre_fim_de_semana(t0, t1):
            continue  # buraco normal de fim de semana
        suspeitos += 1
        if diff_min > maior:
            maior = diff_min
            maior_par = (t0, t1)
    return suspeitos, maior, maior_par


def fmt_gap(minutos):
    if minutos <= 0:
        return "-"
    if minutos < 60:
        return f"{int(minutos)}min"
    if minutos < 1440:
        return f"{minutos/60:.1f}h"
    return f"{minutos/1440:.1f}d"


# ----------------------------------------------------------------------------
# Auditoria + limpeza de um arquivo
# ----------------------------------------------------------------------------
def processar_arquivo(caminho, ativo, tf):
    rel = {
        "arquivo": os.path.basename(caminho), "ativo": ativo, "tf": tf,
        "n_total": 0, "n_validas": 0, "n_parse_err": 0, "n_dupes": 0,
        "n_fora_ordem": 0, "n_ohlc_inv": 0, "n_vol_neg": 0,
        "gaps_susp": 0, "maior_gap": 0.0, "maior_gap_txt": "-",
        "ini": None, "fim": None, "status": "OK", "notas": [],
        "limpos": [],  # lista de tuplas validadas (dt,o,h,l,c,v)
    }

    try:
        with open(caminho, "r", encoding="latin-1", newline="") as f:
            leitor = csv.DictReader(f)
            cols = leitor.fieldnames or []
            if [c.strip().lower() for c in cols] != COLUNAS_ESPERADAS:
                rel["notas"].append(f"cabecalho inesperado: {cols}")
            for row in leitor:
                rel["n_total"] += 1
                try:
                    dt, o, h, lo, c, v = parse_linha(row)
                except (ValueError, KeyError, TypeError, AttributeError):
                    rel["n_parse_err"] += 1
                    continue
                if ohlc_invalido(o, h, lo, c):
                    rel["n_ohlc_inv"] += 1
                    continue
                if v < 0:
                    rel["n_vol_neg"] += 1
                    v = 0
                rel["limpos"].append((dt, o, h, lo, c, v))
    except OSError as e:
        rel["status"] = "FALHA"
        rel["notas"].append(f"erro ao abrir: {e}")
        return rel

    if rel["n_total"] == 0 or not rel["limpos"]:
        rel["status"] = "FALHA"
        rel["notas"].append("nenhuma linha valida")
        return rel

    # fora de ordem (antes de ordenar)
    seq = rel["limpos"]
    for i in range(1, len(seq)):
        if seq[i][0] < seq[i - 1][0]:
            rel["n_fora_ordem"] += 1

    # ordena por datetime e remove duplicatas (mesmo timestamp -> mantem 1o)
    seq.sort(key=lambda t: t[0])
    sem_dup = []
    visto = set()
    for tup in seq:
        if tup[0] in visto:
            rel["n_dupes"] += 1
            continue
        visto.add(tup[0])
        sem_dup.append(tup)
    rel["limpos"] = sem_dup
    rel["n_validas"] = len(sem_dup)
    rel["ini"] = sem_dup[0][0]
    rel["fim"] = sem_dup[-1][0]

    # gaps
    ts = [t[0] for t in sem_dup]
    g, maior, par = contar_gaps(ts, tf)
    rel["gaps_susp"] = g
    rel["maior_gap"] = maior
    rel["maior_gap_txt"] = fmt_gap(maior)
    if par:
        rel["notas"].append(
            f"maior gap {fmt_gap(maior)} entre "
            f"{par[0]:%Y-%m-%d %H:%M} e {par[1]:%Y-%m-%d %H:%M}")

    # decisao de status
    ruins = rel["n_parse_err"] + rel["n_ohlc_inv"]
    pct_ruins = 100.0 * ruins / rel["n_total"] if rel["n_total"] else 0.0
    if pct_ruins >= LIMITE_FALHA_PCT:
        rel["status"] = "FALHA"
        rel["notas"].append(f"{pct_ruins:.1f}% de linhas invalidas")
    elif ruins or rel["n_dupes"] or rel["n_fora_ordem"] or rel["gaps_susp"]:
        rel["status"] = "AVISO"

    return rel


# ----------------------------------------------------------------------------
# Escrita do arquivo limpo
# ----------------------------------------------------------------------------
def escrever_limpo(rel, ativo, tf, dir_saida):
    ativo_limpo = ativo[:-2] if ativo.upper().endswith("-T") else ativo
    pasta = os.path.join(dir_saida, ativo_limpo)
    os.makedirs(pasta, exist_ok=True)
    destino = os.path.join(pasta, f"{tf}_{ativo}.csv")
    with open(destino, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["datetime", "open", "high", "low", "close", "volume"])
        for dt, o, h, lo, c, v in rel["limpos"]:
            w.writerow([dt.strftime("%Y-%m-%d %H:%M:%S"), o, h, lo, c, v])
    return destino


# ----------------------------------------------------------------------------
# Relatorios
# ----------------------------------------------------------------------------
def escrever_relatorios(rels, dir_saida):
    os.makedirs(dir_saida, exist_ok=True)

    # CSV resumo (machine readable)
    csv_path = os.path.join(dir_saida, "qa_resumo.csv")
    with open(csv_path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["arquivo", "ativo", "tf", "status", "barras_validas",
                    "total_lidas", "parse_err", "duplicatas", "fora_ordem",
                    "ohlc_invalido", "vol_neg", "gaps_suspeitos", "maior_gap",
                    "inicio", "fim"])
        for r in rels:
            w.writerow([
                r["arquivo"], r["ativo"], r["tf"], r["status"], r["n_validas"],
                r["n_total"], r["n_parse_err"], r["n_dupes"], r["n_fora_ordem"],
                r["n_ohlc_inv"], r["n_vol_neg"], r["gaps_susp"],
                r["maior_gap_txt"],
                r["ini"].strftime("%Y-%m-%d %H:%M") if r["ini"] else "",
                r["fim"].strftime("%Y-%m-%d %H:%M") if r["fim"] else "",
            ])

    # Markdown legivel
    n_ok = sum(1 for r in rels if r["status"] == "OK")
    n_aviso = sum(1 for r in rels if r["status"] == "AVISO")
    n_falha = sum(1 for r in rels if r["status"] == "FALHA")
    total_barras = sum(r["n_validas"] for r in rels)

    md_path = os.path.join(dir_saida, "RELATORIO_QA.md")
    with open(md_path, "w", encoding="utf-8") as f:
        f.write("# 🩺 Relatório de QA — Dados Brutos TRIVIUM369\n\n")
        f.write(f"- Gerado em: {datetime.now():%Y-%m-%d %H:%M:%S}\n")
        f.write(f"- Arquivos analisados: **{len(rels)}**\n")
        f.write(f"- ✅ OK: **{n_ok}**  |  ⚠️ AVISO: **{n_aviso}**  |  "
                f"❌ FALHA: **{n_falha}**\n")
        f.write(f"- Total de candles válidos: **{total_barras:,}**\n\n")
        f.write("> Gaps são heurísticos: fins de semana são ignorados, mas "
                "feriados podem aparecer como AVISO. AVISO não impede o uso; "
                "FALHA sim.\n\n")
        f.write("| Status | Arquivo | Ativo | TF | Barras | Período | "
                "Dupl. | F.ordem | OHLC inv. | Gaps | Maior gap |\n")
        f.write("|---|---|---|---|---:|---|---:|---:|---:|---:|---|\n")
        icon = {"OK": "✅", "AVISO": "⚠️", "FALHA": "❌"}
        for r in rels:
            periodo = ""
            if r["ini"] and r["fim"]:
                periodo = f"{r['ini']:%Y-%m-%d} → {r['fim']:%Y-%m-%d}"
            f.write("| {st} | {arq} | {at} | {tf} | {n} | {per} | {dup} | "
                    "{ord} | {ohlc} | {gap} | {mg} |\n".format(
                        st=icon.get(r["status"], r["status"]),
                        arq=r["arquivo"], at=r["ativo"], tf=r["tf"],
                        n=f"{r['n_validas']:,}", per=periodo,
                        dup=r["n_dupes"], ord=r["n_fora_ordem"],
                        ohlc=r["n_ohlc_inv"], gap=r["gaps_susp"],
                        mg=r["maior_gap_txt"]))
        # detalhes de FALHA/AVISO com notas
        com_notas = [r for r in rels if r["notas"]]
        if com_notas:
            f.write("\n## 📝 Observações\n\n")
            for r in com_notas:
                f.write(f"- **{r['arquivo']}** ({r['status']}): "
                        f"{'; '.join(r['notas'])}\n")
    return md_path, csv_path


# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
def main(argv=None):
    ap = argparse.ArgumentParser(
        description="QA + consolidacao dos CSVs brutos do MT5 (TRIVIUM369).")
    ap.add_argument("--input", "-i", default=".",
                    help="pasta que contem as DADOS_BRUTOS_* (padrao: atual)")
    ap.add_argument("--output", "-o", default="DADOS_LIMPOS",
                    help="pasta de saida dos dados limpos (padrao: DADOS_LIMPOS)")
    ap.add_argument("--no-clean", action="store_true",
                    help="so audita, nao escreve os arquivos limpos")
    args = ap.parse_args(argv)

    raiz = os.path.abspath(args.input)
    saida = os.path.abspath(args.output)

    print(f"=== QA + CONSOLIDACAO TRIVIUM369 ===")
    print(f"Entrada : {raiz}")
    print(f"Saida   : {saida}\n")

    arquivos = descobrir_csvs(raiz)
    if not arquivos:
        print("[ERRO] Nenhum CSV no padrao <TF>_<ATIVO>-T.csv encontrado.")
        print("       Aponte --input para a pasta que contem as DADOS_BRUTOS_*.")
        return 2

    print(f"Encontrados {len(arquivos)} arquivos. Auditando...\n")
    rels = []
    for caminho, ativo, tf in arquivos:
        r = processar_arquivo(caminho, ativo, tf)
        if not args.no_clean and r["status"] != "FALHA" and r["limpos"]:
            escrever_limpo(r, ativo, tf, saida)
        marca = {"OK": "[OK]   ", "AVISO": "[AVISO]", "FALHA": "[FALHA]"}
        print("{m} {arq:<22} {n:>8} barras  dup={d} ohlc={o} gaps={g}".format(
            m=marca.get(r["status"], r["status"]), arq=r["arquivo"],
            n=r["n_validas"], d=r["n_dupes"], o=r["n_ohlc_inv"],
            g=r["gaps_susp"]))
        rels.append(r)

    md_path, csv_path = escrever_relatorios(rels, saida)

    n_ok = sum(1 for r in rels if r["status"] == "OK")
    n_aviso = sum(1 for r in rels if r["status"] == "AVISO")
    n_falha = sum(1 for r in rels if r["status"] == "FALHA")
    total = sum(r["n_validas"] for r in rels)
    print("\n=== RESUMO ===")
    print(f"OK={n_ok}  AVISO={n_aviso}  FALHA={n_falha}  | "
          f"TOTAL barras validas={total:,}")
    print(f"Relatorio : {md_path}")
    print(f"Resumo CSV: {csv_path}")
    if not args.no_clean:
        print(f"Dados limpos em: {saida}\\<ATIVO>\\<TF>_<ATIVO>-T.csv")

    return 1 if n_falha else 0


if __name__ == "__main__":
    sys.exit(main())
