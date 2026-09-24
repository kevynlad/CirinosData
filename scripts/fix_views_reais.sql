/* ENCODING: arquivo em UTF-8 com BOM. Rodar sempre com sqlcmd usando -C -f 65001 (ex.: sqlcmd -S SQLEXPRESS -E -C -f 65001 -i arquivo.sql) para nao gerar mojibake em Sao Luis / Joao Pessoa / Maceio. */
/* CirinosData — correcao dos views p/ valores reais TSE 2024:
   - Vereador eleito = 'ELEITO POR QP' / 'ELEITO POR MÉDIA' -> usar LIKE 'ELEITO%'
   - Escolaridade real nos dois arquivos = 'SUPERIOR COMPLETO' (sem prefixo ENSINO)
   - Cargo: considerar PREFEITO + VEREADOR (exclui VICE-PREFEITO) */
USE CirinosData;
GO

IF OBJECT_ID('bi.vw_KPI1_Gap','V') IS NOT NULL DROP VIEW bi.vw_KPI1_Gap;
GO
CREATE VIEW bi.vw_KPI1_Gap AS
WITH ele AS (
    SELECT nm_municipio,
        SUM(qtd)*1.0 AS tot,
        SUM(CASE WHEN ds_genero='FEMININO' THEN qtd ELSE 0 END)*1.0/SUM(qtd) AS pct_F_eleit,
        SUM(CASE WHEN ds_raca_cor IN ('PRETA','PARDA') THEN qtd ELSE 0 END)*1.0/SUM(qtd) AS pct_negros_eleit
    FROM tse.eleitorado GROUP BY nm_municipio
),
elt AS (
    SELECT nm_ue AS nm_municipio,
        COUNT(*)*1.0 AS tot,
        SUM(CASE WHEN ds_genero='FEMININO' THEN 1 ELSE 0 END)*1.0/COUNT(*) AS pct_F_eleitos,
        SUM(CASE WHEN ds_cor_raca IN ('PRETA','PARDA') THEN 1 ELSE 0 END)*1.0/COUNT(*) AS pct_negros_eleitos
    FROM tse.candidatos
    WHERE ds_sit_tot_turno LIKE 'ELEITO%' AND ds_cargo IN ('PREFEITO','VEREADOR')
    GROUP BY nm_ue
)
SELECT m.nome AS capital, m.uf,
    ROUND((e.pct_F_eleit - t.pct_F_eleitos)*100,2) AS gap_pp_mulheres,
    ROUND((e.pct_negros_eleit - t.pct_negros_eleitos)*100,2) AS gap_pp_negros
FROM ibge.municipios m
LEFT JOIN ele e ON e.nm_municipio = m.nome
LEFT JOIN elt t ON t.nm_municipio = m.nome
WHERE m.eh_capital = 1;
GO

IF OBJECT_ID('bi.vw_KPI2_Escolaridade','V') IS NOT NULL DROP VIEW bi.vw_KPI2_Escolaridade;
GO
CREATE VIEW bi.vw_KPI2_Escolaridade AS
WITH a AS (
    SELECT nm_municipio,
        SUM(CASE WHEN ds_grau_instrucao='SUPERIOR COMPLETO' THEN qtd ELSE 0 END)*1.0/SUM(qtd) AS pct_sup_eleit
    FROM tse.eleitorado GROUP BY nm_municipio
),
b AS (
    SELECT nm_ue AS nm_municipio,
        SUM(CASE WHEN ds_grau_instrucao='SUPERIOR COMPLETO' THEN 1 ELSE 0 END)*1.0/COUNT(*) AS pct_sup_eleitos
    FROM tse.candidatos WHERE ds_sit_tot_turno LIKE 'ELEITO%' AND ds_cargo IN ('PREFEITO','VEREADOR') GROUP BY nm_ue
)
SELECT m.nome AS capital, m.uf,
    ROUND(a.pct_sup_eleit*100,2) AS pct_sup_eleitorado,
    ROUND(b.pct_sup_eleitos*100,2) AS pct_sup_eleitos,
    ROUND(b.pct_sup_eleitos/NULLIF(a.pct_sup_eleit,0),2) AS indice_sobrerrep
FROM ibge.municipios m
LEFT JOIN a ON a.nm_municipio = m.nome
LEFT JOIN b ON b.nm_municipio = m.nome
WHERE m.eh_capital = 1;
GO

IF OBJECT_ID('bi.vw_KPI3_Renovacao','V') IS NOT NULL DROP VIEW bi.vw_KPI3_Renovacao;
GO
CREATE VIEW bi.vw_KPI3_Renovacao AS
SELECT m.nome AS capital, m.uf,
    COUNT(c.id) AS total_eleitos,
    ROUND(SUM(CASE WHEN c.ds_ocupacao NOT IN ('VEREADOR','PREFEITO','DEPUTADO ESTADUAL','DEPUTADO FEDERAL','SENADOR') THEN 1 ELSE 0 END)*100.0/NULLIF(COUNT(*),0),2) AS taxa_ampla_sem_mandato,
    -- NULL quando sem base histórica (2020/2016): 100% seria falso; hist cruza por NR_TITULO (CPF é mascarado)
    CASE WHEN (SELECT COUNT(*) FROM tse.candidatos_hist) = 0 THEN NULL
      ELSE ROUND(SUM(CASE WHEN c.id IS NOT NULL AND h.nr_cpf IS NULL THEN 1 ELSE 0 END)*100.0/NULLIF(COUNT(c.id),0),2) END AS taxa_estrita_nunca_candidato
FROM ibge.municipios m
LEFT JOIN tse.candidatos c ON c.nm_ue = m.nome AND c.ds_sit_tot_turno LIKE 'ELEITO%' AND c.ds_cargo IN ('PREFEITO','VEREADOR')
LEFT JOIN tse.candidatos_hist h ON h.nr_cpf = c.nr_cpf
WHERE m.eh_capital = 1
GROUP BY m.nome, m.uf;
GO
