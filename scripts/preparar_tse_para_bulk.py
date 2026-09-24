"""
CirinosData — Prepara CSVs brutos do TSE para BULK INSERT.
Uso:
  python scripts\\preparar_tse_para_bulk.py
Lê:    data\\tse\\raw\\*.csv (eleitorado por UF + consulta_cand_2024 (+ 2020/2016 p/ hist))
Gera:  data\\tse\\clean\\tse_eleitorado_clean.csv
       data\\tse\\clean\\tse_candidatos_clean.csv
       data\\tse\\clean\\tse_candidatos_hist_clean.csv
"""
from pathlib import Path
import unicodedata
import pandas as pd

BASE = Path(__file__).resolve().parents[1]
RAW = BASE / "data" / "tse" / "raw"
CLEAN = BASE / "data" / "tse" / "clean"

# Nome canônico (igual a ibge.municipios.nome) por chave normalizada
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

def norm(s: str) -> str:
    s = str(s).strip().upper()
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    s = " ".join(s.split())
    return s

def read_tse(path: Path) -> pd.DataFrame:
    for enc in ("latin1", "utf-8-sig", "utf-8"):
        for sep in (";", ","):
            try:
                df = pd.read_csv(path, sep=sep, encoding=enc, dtype=str, engine="python")
                if len(df.columns) >= 3:
                    df.columns = [str(c).strip().upper() for c in df.columns]
                    return df
            except Exception:
                continue
    raise RuntimeError(f"Não consegui ler {path.name}")

def main():
    CLEAN.mkdir(parents=True, exist_ok=True)
    files = sorted(list(RAW.rglob("*.csv")) + list(RAW.rglob("*.txt")))
    files = [f for f in files if f.suffix.lower() in (".csv", ".txt")]
    if not files:
        print(f"[VAZIO] Nenhum CSV em {RAW}")
        print("Baixe no navegador (dadosabertos.tse.jus.br bloqueia robô com 403):")
        print(" 1) dataset eleitorado-2024 -> Perfil do eleitorado por secao (MA,PI,CE,RN,PB,PE,AL,SE,BA)")
        print(" 2) dataset resultados-2024 -> consulta_cand_2024 (+ 2020/2016 p/ KPI3 estrito)")
        print("Extraia os ZIPs e coloque os .csv aqui, depois rode de novo.")
        return

    ele_parts, cand_parts, hist_cpfs = [], [], set()

    for f in files:
        df = read_tse(f)
        cols = set(df.columns)
        print(f"\n-- {f.name}: {len(df)} linhas, cols={sorted(list(cols))[:12]}...")

        if "DS_SIT_TOT_TURNO" in cols and "DS_CARGO" in cols:
            # ---- CANDIDATOS ----
            get = lambda *names: next((c for c in names if c in cols), None)
            c_uf = get("SG_UF", "SG_UF_NASCIMENTO")
            c_mun = get("NM_UE", "NM_MUNICIPIO")
            c_part = get("SG_PARTIDO", "SG_LEGENDA", "NR_PARTIDO")
            c_cpf = get("NR_CPF_CANDIDATO", "NR_CPF", "NR_CPF_CANDIDATO")
            out = pd.DataFrame({
                "sg_uf": df[c_uf] if c_uf else "",
                "nm_ue_raw": df[c_mun] if c_mun else "",
                "ds_cargo": df["DS_CARGO"],
                "ds_sit_tot_turno": df["DS_SIT_TOT_TURNO"],
                "ds_genero": df["DS_GENERO"] if "DS_GENERO" in cols else "",
                "ds_cor_raca": df["DS_COR_RACA"] if "DS_COR_RACA" in cols else "",
                "ds_grau_instrucao": df["DS_GRAU_INSTRUCAO"] if "DS_GRAU_INSTRUCAO" in cols else "",
                "nr_cpf": df[c_cpf] if c_cpf else "",
                "ds_ocupacao": df["DS_OCUPACAO"] if "DS_OCUPACAO" in cols else "",
                "sg_partido": df[c_part] if c_part else "",
            })
            out["key"] = out["nm_ue_raw"].map(norm)
            out = out[out["key"].isin(CANON.keys())].copy()
            out["nm_ue"] = out["key"].map(CANON)
            out = out.drop(columns=["nm_ue_raw", "key"])
            print(f"   candidatos nas 9 capitais: {len(out)}")
            cand_parts.append(out)
            # se o arquivo for 2020/2016, acumula CPFs p/ hist
            if any(a in f.name for a in ("2020", "2016", " hist")):
                hist_cpfs.update(out["nr_cpf"].dropna().astype(str).str.strip().unique().tolist())
            else:
                # 2024 também conta como CPF conhecido? Não p/ hist — hist é só <2024
                pass
        elif "DS_GENERO" in cols and any(c.startswith("QT_ELEITOR") for c in cols):
            # ---- ELEITORADO ----
            qcol = next(c for c in cols if c.startswith("QT_ELEITOR"))
            c_mun = "NM_MUNICIPIO" if "NM_MUNICIPIO" in cols else next((c for c in ["NM_MUNICIPIO", "NM_UE"] if c in cols), None)
            c_grau = "DS_GRAU_ESCOLARIDADE" if "DS_GRAU_ESCOLARIDADE" in cols else "DS_GRAU_INSTRUCAO"
            c_raca = "DS_RACA_COR" if "DS_RACA_COR" in cols else "DS_COR_RACA"
            tmp = pd.DataFrame({
                "sg_uf": df["SG_UF"],
                "nm_raw": df[c_mun],
                "ds_genero": df["DS_GENERO"],
                "ds_raca_cor": df[c_raca] if c_raca in cols else "NAO INFORMADO",
                "ds_grau_instrucao": df[c_grau] if c_grau in cols else "NAO INFORMADO",
                "qtd": pd.to_numeric(df[qcol], errors="coerce").fillna(0).astype(int),
            })
            tmp["key"] = tmp["nm_raw"].map(norm)
            tmp = tmp[tmp["key"].isin(CANON.keys())].copy()
            tmp["nm_municipio"] = tmp["key"].map(CANON)
            g = tmp.groupby(["sg_uf", "nm_municipio", "ds_genero", "ds_raca_cor", "ds_grau_instrucao"], as_index=False)["qtd"].sum()
            print(f"   eleitorado agregado nas 9 capitais: {len(g)} grupos, {int(g['qtd'].sum())} eleitores")
            ele_parts.append(g)
        else:
            print("   IGNORADO: header não reconhecido como eleitorado nem candidatos. Me mande o header que eu adapto.")

    if ele_parts:
        ele = pd.concat(ele_parts, ignore_index=True)
        ele = ele.groupby(["sg_uf", "nm_municipio", "ds_genero", "ds_raca_cor", "ds_grau_instrucao"], as_index=False)["qtd"].sum()
        ele.to_csv(CLEAN / "tse_eleitorado_clean.csv", index=False, encoding="utf-8")
        print(f"\n[OK] {CLEAN / 'tse_eleitorado_clean.csv'} ({len(ele)} linhas)")
    if cand_parts:
        cand = pd.concat(cand_parts, ignore_index=True)
        # remove duplicados entre arquivos (mesmo CPF+ano+UE+cargo)
        cand = cand.drop_duplicates()
        cand.to_csv(CLEAN / "tse_candidatos_clean.csv", index=False, encoding="utf-8")
        print(f"[OK] {CLEAN / 'tse_candidatos_clean.csv'} ({len(cand)} linhas)")
        # hist: CPFs de 2020/2016 distintos
        if hist_cpfs:
            hist_cpfs = {c for c in hist_cpfs if c and c.lower() != "nan"}
            pd.DataFrame({"nr_cpf": sorted(hist_cpfs)}).to_csv(CLEAN / "tse_candidatos_hist_clean.csv", index=False, encoding="utf-8")
            print(f"[OK] hist ({len(hist_cpfs)} CPFs)")
        else:
            print("[AVISO] Sem arquivos 2020/2016 -> KPI3 estrita ficará NULL. Baixe consulta_cand_2020 e 2016 e rode de novo.")
            print("        A KPI3 ampla (sem mandato prévio) funciona só com 2024.")

if __name__ == "__main__":
    main()
