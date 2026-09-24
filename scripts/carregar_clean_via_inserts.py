"""Lê clean/*.csv e gera carga_clean_inserts.sql com N'' unicode + batches."""
from pathlib import Path
import pandas as pd

BASE = Path(__file__).resolve().parents[1]
CLEAN = BASE / "data" / "tse" / "clean"
OUT = BASE / "scripts" / "carga_clean_inserts.sql"

def q(v):
    if pd.isna(v):
        return "NULL"
    if isinstance(v, (int,)):
        return str(v)
    s = str(v).replace("'", "''")
    try:
        # numero puro?
        if s.isdigit():
            return s
    except Exception:
        pass
    return f"N'{s}'"

def num(v):
    try:
        return str(int(float(v)))
    except Exception:
        return "0"

lines = ["USE CirinosData;", "GO", "DELETE FROM tse.candidatos;", "DELETE FROM tse.eleitorado;",
         "DELETE FROM tse.candidatos_hist;", "GO"]

ele = pd.read_csv(CLEAN / "tse_eleitorado_clean.csv", dtype=str).fillna("")
lines.append("-- eleitorado")
batch = []
for _, r in ele.iterrows():
    batch.append(f"({q(r['sg_uf'])},{q(r['nm_municipio'])},{q(r['ds_genero'])},{q(r['ds_raca_cor'])},{q(r['ds_grau_instrucao'])},{num(r['qtd'])})")
    if len(batch) >= 500:
        lines.append("INSERT INTO tse.eleitorado (sg_uf,nm_municipio,ds_genero,ds_raca_cor,ds_grau_instrucao,qtd) VALUES " + ",".join(batch) + ";")
        batch = []
if batch:
    lines.append("INSERT INTO tse.eleitorado (sg_uf,nm_municipio,ds_genero,ds_raca_cor,ds_grau_instrucao,qtd) VALUES " + ",".join(batch) + ";")
lines.append("GO")

cand = pd.read_csv(CLEAN / "tse_candidatos_clean.csv", dtype=str).fillna("")
lines.append("-- candidatos")
batch = []
for _, r in cand.iterrows():
    batch.append(f"({q(r['sg_uf'])},{q(r['nm_ue'])},{q(r['ds_cargo'])},{q(r['ds_sit_tot_turno'])},{q(r['ds_genero'])},{q(r['ds_cor_raca'])},{q(r['ds_grau_instrucao'])},{q(r['nr_cpf'])},{q(r['ds_ocupacao'])},{q(r['sg_partido'])})")
    if len(batch) >= 200:
        lines.append("INSERT INTO tse.candidatos (sg_uf,nm_ue,ds_cargo,ds_sit_tot_turno,ds_genero,ds_cor_raca,ds_grau_instrucao,nr_cpf,ds_ocupacao,sg_partido) VALUES " + ",".join(batch) + ";")
        batch = []
if batch:
    lines.append("INSERT INTO tse.candidatos (sg_uf,nm_ue,ds_cargo,ds_sit_tot_turno,ds_genero,ds_cor_raca,ds_grau_instrucao,nr_cpf,ds_ocupacao,sg_partido) VALUES " + ",".join(batch) + ";")
lines.append("GO")

hp = CLEAN / "tse_candidatos_hist_clean.csv"
if hp.exists() and hp.stat().st_size > 50:
    hist = pd.read_csv(hp, dtype=str).fillna("")
    lines.append("-- hist")
    batch = []
    for _, r in hist.iterrows():
        batch.append(f"({q(r['nr_cpf'])},{num(r['ano_primeira_candidatura'])})")
        if len(batch) >= 500:
            lines.append("INSERT INTO tse.candidatos_hist (nr_cpf,ano_primeira_candidatura) VALUES " + ",".join(batch) + ";")
            batch = []
    if batch:
        lines.append("INSERT INTO tse.candidatos_hist (nr_cpf,ano_primeira_candidatura) VALUES " + ",".join(batch) + ";")
    lines.append("GO")

OUT.write_text("\n".join(lines), encoding="utf-8")
print(f"OK {OUT} ({len(lines)} linhas)")
