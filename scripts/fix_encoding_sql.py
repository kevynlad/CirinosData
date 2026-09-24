"""Garante BOM UTF-8 + header de encoding nos .sql do projeto."""
from pathlib import Path

BASE = Path(__file__).resolve().parents[1]
HEADER = (
    "/* ENCODING: arquivo em UTF-8 com BOM. "
    "Rodar sempre com sqlcmd usando -C -f 65001 "
    "(ex.: sqlcmd -S SQLEXPRESS -E -C -f 65001 -i arquivo.sql) "
    "para nao gerar mojibake em Sao Luis / Joao Pessoa / Maceio. */\n"
)
for f in ["CirinosData_TSE_NE.sql", "scripts/fix_views_reais.sql", "scripts/fix_nomes.sql"]:
    p = BASE / f
    t = p.read_text(encoding="utf-8-sig")
    if "ENCODING:" not in t:
        t = HEADER + t
    p.write_text(t, encoding="utf-8-sig")
    print("BOM+header ok:", f)
