"""Massa SINTETICA p/ desenvolvimento — NÃO é dado oficial TSE.
Substitua pelos CSVs reais quando baixar no navegador.
Gera os 3 clean no formato do BULK real."""
from pathlib import Path
import random
import pandas as pd

BASE = Path(__file__).resolve().parents[1]
CLEAN = BASE / "data" / "tse" / "clean"
CLEAN.mkdir(parents=True, exist_ok=True)
random.seed(42)

CAPS = [
    ("MA", "São Luís", 1037775, 31),
    ("PI", "Teresina", 866300, 29),
    ("CE", "Fortaleza", 2428708, 43),
    ("RN", "Natal", 751300, 25),
    ("PB", "João Pessoa", 833932, 27),
    ("PE", "Recife", 1488920, 37),
    ("AL", "Maceió", 957916, 27),
    ("SE", "Aracaju", 602757, 26),
    ("BA", "Salvador", 2417678, 43),
]
RACAS = [("PARDA", .52), ("BRANCA", .24), ("PRETA", .13), ("AMARELA", .01), ("INDIGENA", .01), ("NAO INFORMADO", .09)]
ESC_ELEIT = [("ENSINO FUNDAMENTAL INCOMPLETO", .22), ("ENSINO FUNDAMENTAL COMPLETO", .10),
    ("ENSINO MEDIO INCOMPLETO", .08), ("ENSINO MEDIO COMPLETO", .28),
    ("ENSINO SUPERIOR INCOMPLETO", .08), ("ENSINO SUPERIOR COMPLETO", .13), ("NAO INFORMADO", .11)]
PARTIDOS = ["PT", "PL", "MDB", "PP", "PSD", "PDT", "PSB", "REPUBLICANOS", "UNIAO", "PODE"]
OCUP_MANDATO = ["VEREADOR", "PREFEITO", "DEPUTADO ESTADUAL", "DEPUTADO FEDERAL"]
OCUP_OUTRAS = ["ADVOGADO", "PROFESSOR", "EMPRESARIO", "MEDICO", "SERVIDOR PUBLICO", "COMERCIANTE", "ENFERMEIRO"]

ele_rows, cand_rows, hist_rows = [], [], []
cpf_seq = 100000000

for uf, mun, pop, n_ver in CAPS:
    eleitorado = int(pop * 0.72)
    for sexo, p_sexo in (("FEMININO", .53), ("MASCULINO", .47)):
        for raca, p_raca in RACAS:
            for esc, p_esc in ESC_ELEIT:
                q = int(eleitorado * p_sexo * p_raca * p_esc / 0.5)  # /0.5 p/ compensar agregacao dupla sexo? ajustado abaixo
                ele_rows.append((uf, mun, sexo, raca, esc, q))
    # normaliza p/ total do municipio = eleitorado (só as linhas deste município)
    idx = [i for i, r in enumerate(ele_rows) if r[1] == mun]
    tot = sum(ele_rows[i][5] for i in idx)
    fator = eleitorado / tot if tot else 0
    for i in idx:
        u, m, s, r, e, qq = ele_rows[i]
        ele_rows[i] = (u, m, s, r, e, int(qq * fator))

    # --- eleitos: 1 prefeito + n_ver vereadores ---
    for i in range(n_ver + 1):
        cargo = "PREFEITO" if i == 0 else "VEREADOR"
        sexo = "FEMININO" if random.random() < 0.18 else "MASCULINO"
        raca = random.choices(["PARDA", "BRANCA", "PRETA", "AMARELA", "INDIGENA"],
                              weights=[.48, .32, .15, .03, .02])[0]
        esc = "SUPERIOR COMPLETO" if random.random() < 0.62 else random.choice(
            ["ENSINO MEDIO COMPLETO", "ENSINO SUPERIOR INCOMPLETO", "ENSINO MEDIO INCOMPLETO"])
        cpf_seq += random.randint(1009, 9999)
        cpf = f"{cpf_seq:011d}"
        ocup = random.choice(OCUP_MANDATO) if random.random() < 0.45 else random.choice(OCUP_OUTRAS)
        cand_rows.append((uf, mun, cargo, "ELEITO", sexo, raca, esc, cpf, ocup, random.choice(PARTIDOS)))
        # 55% já foram candidatos antes -> entram no hist (taxa estrita ~45% novatos)
        if random.random() < 0.55:
            hist_rows.append((cpf, random.choice([2016, 2020])))

pd.DataFrame(ele_rows, columns=["sg_uf", "nm_municipio", "ds_genero", "ds_raca_cor", "ds_grau_instrucao", "qtd"]
    ).to_csv(CLEAN / "tse_eleitorado_clean.csv", index=False, encoding="utf-8")
pd.DataFrame(cand_rows, columns=["sg_uf", "nm_ue", "ds_cargo", "ds_sit_tot_turno", "ds_genero",
    "ds_cor_raca", "ds_grau_instrucao", "nr_cpf", "ds_ocupacao", "sg_partido"]
    ).to_csv(CLEAN / "tse_candidatos_clean.csv", index=False, encoding="utf-8")
pd.DataFrame(hist_rows, columns=["nr_cpf", "ano_primeira_candidatura"]
    ).drop_duplicates().to_csv(CLEAN / "tse_candidatos_hist_clean.csv", index=False, encoding="utf-8")
print(f"OK sintético: eleitorado={len(ele_rows)} grupos, candidatos={len(cand_rows)}, hist={len(hist_rows)}")
print("AVISO: dados SINTÉTICOS p/ desenvolvimento. Trocar pelos reais antes da banca.")
