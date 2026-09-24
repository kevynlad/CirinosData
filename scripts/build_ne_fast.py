"""Build rapido NE: le so os 9 UFs, filtra 9 capitais, gera clean p/ BULK."""
from pathlib import Path
import unicodedata
import pandas as pd

BASE = Path(__file__).resolve().parents[1]
RAW_ELE = BASE / "data" / "tse" / "raw" / "perfil_eleitorado_2024"
RAW_CAND = BASE / "data" / "tse" / "raw" / "consulta_cand_2024"
CLEAN = BASE / "data" / "tse" / "clean"
CLEAN.mkdir(parents=True, exist_ok=True)

UFS = ["MA", "PI", "CE", "RN", "PB", "PE", "AL", "SE", "BA"]
CANON = {
    "SAO LUIS": "São Luís",
    "TERESINA": "Teresina",
    "FORTALEZA": "Fortaleza",
    "NATAL": "Natal",
    "JOAO PESSOA": "João Pessoa",
    "RECIFE": "Recife",
    "MACEIO": "Maceió",
    "ARACAJU": "Aracaju",
    "SALVADOR": "Salvador",
}

def norm(s):
    s = str(s).strip().upper()
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    return " ".join(s.split())

ELE_COLS = ["SG_UF", "NM_MUNICIPIO", "DS_GENERO", "DS_RACA_COR", "DS_GRAU_ESCOLARIDADE", "QT_ELEITORES"]
CAND_COLS = ["SG_UF", "NM_UE", "DS_CARGO", "DS_SIT_TOT_TURNO", "DS_GENERO",
             "DS_COR_RACA", "DS_GRAU_INSTRUCAO", "NR_CPF_CANDIDATO", "DS_OCUPACAO", "SG_PARTIDO"]

ele_parts = []
for uf in UFS:
    f = RAW_ELE / f"perfil_eleitorado_2024_{uf}.csv"
    print(f"Lendo {f.name} ...", flush=True)
    df = pd.read_csv(f, sep=";", encoding="latin1", usecols=ELE_COLS, dtype=str, engine="python")
    df["key"] = df["NM_MUNICIPIO"].map(norm)
    df = df[df["key"].isin(CANON.keys())].copy()
    df["nm_municipio"] = df["key"].map(CANON)
    df["qtd"] = pd.to_numeric(df["QT_ELEITORES"], errors="coerce").fillna(0).astype(int)
    g = df.groupby(["SG_UF", "nm_municipio", "DS_GENERO", "DS_RACA_COR", "DS_GRAU_ESCOLARIDADE"], as_index=False)["qtd"].sum()
    g = g.rename(columns={"DS_GRAU_ESCOLARIDADE": "ds_grau_instrucao", "DS_GENERO": "ds_genero", "DS_RACA_COR": "ds_raca_cor", "SG_UF": "sg_uf"})
    ele_parts.append(g)
    print(f"  -> {len(g)} grupos, {int(g['qtd'].sum())} eleitores", flush=True)

ele = pd.concat(ele_parts, ignore_index=True)
ele = ele.groupby(["sg_uf", "nm_municipio", "ds_genero", "ds_raca_cor", "ds_grau_instrucao"], as_index=False)["qtd"].sum()
ele.to_csv(CLEAN / "tse_eleitorado_clean.csv", index=False, encoding="utf-8")
print(f"[OK] eleitorado {len(ele)} linhas, total={int(ele['qtd'].sum())}")

cand_parts = []
for uf in UFS:
    f = RAW_CAND / f"consulta_cand_2024_{uf}.csv"
    print(f"Lendo {f.name} ...", flush=True)
    df = pd.read_csv(f, sep=";", encoding="latin1", usecols=CAND_COLS, dtype=str, engine="python")
    df["key"] = df["NM_UE"].map(norm)
    df = df[df["key"].isin(CANON.keys())].copy()
    df["nm_ue"] = df["key"].map(CANON)
    out = pd.DataFrame({
        "sg_uf": df["SG_UF"],
        "nm_ue": df["nm_ue"],
        "ds_cargo": df["DS_CARGO"],
        "ds_sit_tot_turno": df["DS_SIT_TOT_TURNO"],
        "ds_genero": df["DS_GENERO"],
        "ds_cor_raca": df["DS_COR_RACA"],
        "ds_grau_instrucao": df["DS_GRAU_INSTRUCAO"],
        "nr_cpf": df["NR_CPF_CANDIDATO"],
        "ds_ocupacao": df["DS_OCUPACAO"],
        "sg_partido": df["SG_PARTIDO"],
    })
    cand_parts.append(out)
    print(f"  -> {len(out)} candidatos nas capitais ({uf})", flush=True)

cand = pd.concat(cand_parts, ignore_index=True).drop_duplicates()
cand.to_csv(CLEAN / "tse_candidatos_clean.csv", index=False, encoding="utf-8")
print(f"[OK] candidatos {len(cand)} linhas")
print("Eleitos por capital:")
print(cand[cand["ds_sit_tot_turno"] == "ELEITO"].groupby("nm_ue").size().to_string())
# hist vazio (sem 2020/2016) — cria arquivo so com header p/ BULK nao falhar
pd.DataFrame(columns=["nr_cpf", "ano_primeira_candidatura"]).to_csv(CLEAN / "tse_candidatos_hist_clean.csv", index=False, encoding="utf-8")
print("[OK] hist vazio (sem base 2020/2016)")
