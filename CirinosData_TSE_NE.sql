/* ENCODING: arquivo em UTF-8 com BOM. Rodar sempre com sqlcmd usando -C -f 65001 (ex.: sqlcmd -S SQLEXPRESS -E -C -f 65001 -i arquivo.sql) para nao gerar mojibake em Sao Luis / Joao Pessoa / Maceio. */
/* ============================================================
   CirinosData — Banco TSE Nordeste (SQL Server / T-SQL)
   Projeto: Innovation Lab Applied BI + Relational DB (T-SQL)
   Escopo: 9 capitais do Nordeste | IBGE Censo 2022 + TSE 2024
   Servidor testado: .\SQLEXPRESS  (usar sqlcmd -S ".\SQLEXPRESS" -E -C)
   ============================================================ */

IF DB_ID('CirinosData') IS NULL
    CREATE DATABASE CirinosData;
GO
USE CirinosData;
GO

/* ---------- Schemas ---------- */
IF SCHEMA_ID('ibge') IS NULL EXEC('CREATE SCHEMA ibge');
IF SCHEMA_ID('tse')  IS NULL EXEC('CREATE SCHEMA tse');
IF SCHEMA_ID('bi')   IS NULL EXEC('CREATE SCHEMA bi');
GO

/* ---------- 1) Base IBGE (real, via SIDRA t/9514 v/93 Censo 2022) ---------- */
IF OBJECT_ID('ibge.municipios','U') IS NOT NULL DROP TABLE ibge.municipios;
GO
CREATE TABLE ibge.municipios (
    cod_ibge   INT PRIMARY KEY,
    nome       VARCHAR(100) NOT NULL,
    uf         CHAR(2) NOT NULL,
    regiao     CHAR(2) NOT NULL DEFAULT 'NE',
    eh_capital BIT NOT NULL DEFAULT 1,
    pop_2022   INT NOT NULL
);
GO
INSERT INTO ibge.municipios (cod_ibge, nome, uf, regiao, eh_capital, pop_2022) VALUES
(2111300, 'São Luís',    'MA', 'NE', 1, 1037775),
(2211001, 'Teresina',    'PI', 'NE', 1, 866300),
(2304400, 'Fortaleza',   'CE', 'NE', 1, 2428708),
(2408102, 'Natal',       'RN', 'NE', 1, 751300),
(2507507, 'João Pessoa', 'PB', 'NE', 1, 833932),
(2611606, 'Recife',      'PE', 'NE', 1, 1488920),
(2704302, 'Maceió',      'AL', 'NE', 1, 957916),
(2800308, 'Aracaju',     'SE', 'NE', 1, 602757),
(2927408, 'Salvador',    'BA', 'NE', 1, 2417678);
GO

/* ---------- 2) Staging TSE (carga via BULK INSERT dos CSVs baixados no navegador) ----------
   Arquivos: dadosabertos.tse.jus.br -> Eleitorado 2024 (perfil por secao, por UF)
             + Resultados 2024 (consulta_cand_2024)
   Layout simplificado: agregar o CSV por grupo demografico antes do BULK,
   ou ajustar os nomes de coluna ao header oficial e recarregar.
-------------------------------------------------------------------------- */
IF OBJECT_ID('tse.eleitorado','U') IS NOT NULL DROP TABLE tse.eleitorado;
GO
CREATE TABLE tse.eleitorado (
    id INT IDENTITY(1,1) PRIMARY KEY,
    sg_uf VARCHAR(2) NOT NULL,
    nm_municipio VARCHAR(100) NOT NULL,
    ds_genero VARCHAR(20) NOT NULL,        -- FEMININO / MASCULINO
    ds_raca_cor VARCHAR(30) NOT NULL,      -- PRETA / PARDA / BRANCA / INDIGENA / AMARELA
    ds_grau_instrucao VARCHAR(50) NOT NULL,-- ex: ENSINO SUPERIOR COMPLETO
    qtd INT NOT NULL
);
GO

IF OBJECT_ID('tse.candidatos','U') IS NOT NULL DROP TABLE tse.candidatos;
GO
CREATE TABLE tse.candidatos (
    id INT IDENTITY(1,1) PRIMARY KEY,
    sg_uf VARCHAR(2) NOT NULL,
    nm_ue VARCHAR(100) NOT NULL,           -- municipio da candidatura
    ds_cargo VARCHAR(30) NOT NULL,         -- PREFEITO / VEREADOR
    ds_sit_tot_turno VARCHAR(30) NOT NULL, -- ELEITO / NAO ELEITO etc
    ds_genero VARCHAR(20) NULL,
    ds_cor_raca VARCHAR(30) NULL,
    ds_grau_instrucao VARCHAR(50) NULL,
    nr_cpf VARCHAR(14) NULL,               -- para cruzar 2016/2020 (KPI3 estrito)
    ds_ocupacao VARCHAR(100) NULL,
    sg_partido VARCHAR(20) NULL
);
GO

/* Histórico para KPI3 estrito (novato = nunca foi candidato antes) */
IF OBJECT_ID('tse.candidatos_hist','U') IS NOT NULL DROP TABLE tse.candidatos_hist;
GO
CREATE TABLE tse.candidatos_hist (
    nr_cpf VARCHAR(14) PRIMARY KEY,
    ano_primeira_candidatura INT NOT NULL
);
GO

/* ---------- 3) Views dos KPIs ---------- */

/* KPI 1 — Gap de Representatividade (pp) */
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

/* KPI 2 — Indice de Sobrerrepresentacao por escolaridade */
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

/* KPI 3 — Taxa de Renovacao (ampla + estrita) */
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

/* ---------- 4) Modelo estrela (fato + dimensões) ---------- */
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw');
GO

IF OBJECT_ID('dw.dim_municipio','U') IS NOT NULL DROP TABLE dw.fato_eleitos;
IF OBJECT_ID('dw.fato_eleitorado','U') IS NOT NULL DROP TABLE dw.fato_eleitorado;
IF OBJECT_ID('dw.dim_municipio','U') IS NOT NULL DROP TABLE dw.dim_municipio;
IF OBJECT_ID('dw.dim_genero','U') IS NOT NULL DROP TABLE dw.dim_genero;
IF OBJECT_ID('dw.dim_raca_cor','U') IS NOT NULL DROP TABLE dw.dim_raca_cor;
IF OBJECT_ID('dw.dim_escolaridade','U') IS NOT NULL DROP TABLE dw.dim_escolaridade;
IF OBJECT_ID('dw.dim_cargo','U') IS NOT NULL DROP TABLE dw.dim_cargo;
IF OBJECT_ID('dw.dim_partido','U') IS NOT NULL DROP TABLE dw.dim_partido;
GO

CREATE TABLE dw.dim_municipio (
    sk_municipio INT IDENTITY(1,1) PRIMARY KEY,
    cod_ibge INT NOT NULL UNIQUE,
    nome VARCHAR(100) NOT NULL,
    uf CHAR(2) NOT NULL,
    regiao CHAR(2) NOT NULL DEFAULT 'NE',
    pop_2022 INT NOT NULL
);
CREATE TABLE dw.dim_genero (sk_genero INT IDENTITY(1,1) PRIMARY KEY, ds_genero VARCHAR(20) NOT NULL UNIQUE);
CREATE TABLE dw.dim_raca_cor (sk_raca INT IDENTITY(1,1) PRIMARY KEY, ds_raca_cor VARCHAR(30) NOT NULL UNIQUE);
CREATE TABLE dw.dim_escolaridade (sk_esc INT IDENTITY(1,1) PRIMARY KEY, ds_grau VARCHAR(50) NOT NULL UNIQUE);
CREATE TABLE dw.dim_cargo (sk_cargo INT IDENTITY(1,1) PRIMARY KEY, ds_cargo VARCHAR(30) NOT NULL UNIQUE);
CREATE TABLE dw.dim_partido (sk_partido INT IDENTITY(1,1) PRIMARY KEY, sg_partido VARCHAR(20) NOT NULL UNIQUE);
GO

CREATE TABLE dw.fato_eleitorado (
    sk_municipio INT NOT NULL REFERENCES dw.dim_municipio(sk_municipio),
    sk_genero INT NOT NULL REFERENCES dw.dim_genero(sk_genero),
    sk_raca INT NOT NULL REFERENCES dw.dim_raca_cor(sk_raca),
    sk_esc INT NOT NULL REFERENCES dw.dim_escolaridade(sk_esc),
    qtd_eleitores INT NOT NULL,
    PRIMARY KEY (sk_municipio, sk_genero, sk_raca, sk_esc)
);
CREATE TABLE dw.fato_eleitos (
    id INT IDENTITY(1,1) PRIMARY KEY,
    sk_municipio INT NOT NULL REFERENCES dw.dim_municipio(sk_municipio),
    sk_genero INT NOT NULL REFERENCES dw.dim_genero(sk_genero),
    sk_raca INT NOT NULL REFERENCES dw.dim_raca_cor(sk_raca),
    sk_esc INT NOT NULL REFERENCES dw.dim_escolaridade(sk_esc),
    sk_cargo INT NOT NULL REFERENCES dw.dim_cargo(sk_cargo),
    sk_partido INT NOT NULL REFERENCES dw.dim_partido(sk_partido),
    flag_novato_estrito BIT NOT NULL DEFAULT 0,
    flag_sem_mandato BIT NOT NULL DEFAULT 0
);
GO

/* Carga DW a partir da staging (rodar após BULK INSERT em tse.*) */
IF OBJECT_ID('dw.sp_carga_dw','P') IS NOT NULL DROP PROCEDURE dw.sp_carga_dw;
GO
CREATE PROCEDURE dw.sp_carga_dw AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dw.dim_municipio (cod_ibge, nome, uf, regiao, pop_2022)
      SELECT cod_ibge, nome, uf, regiao, pop_2022 FROM ibge.municipios m
      WHERE NOT EXISTS (SELECT 1 FROM dw.dim_municipio d WHERE d.cod_ibge = m.cod_ibge);

    INSERT INTO dw.dim_genero (ds_genero)
      SELECT DISTINCT ds_genero FROM tse.eleitorado
      WHERE ds_genero NOT IN (SELECT ds_genero FROM dw.dim_genero)
      UNION SELECT DISTINCT ds_genero FROM tse.candidatos
      WHERE ds_genero NOT IN (SELECT ds_genero FROM dw.dim_genero) AND ds_genero IS NOT NULL;

    INSERT INTO dw.dim_raca_cor (ds_raca_cor)
      SELECT DISTINCT ds_raca_cor FROM tse.eleitorado
      WHERE ds_raca_cor NOT IN (SELECT ds_raca_cor FROM dw.dim_raca_cor)
      UNION SELECT DISTINCT ds_cor_raca FROM tse.candidatos
      WHERE ds_cor_raca NOT IN (SELECT ds_raca_cor FROM dw.dim_raca_cor) AND ds_cor_raca IS NOT NULL;

    INSERT INTO dw.dim_escolaridade (ds_grau)
      SELECT DISTINCT ds_grau_instrucao FROM tse.eleitorado
      WHERE ds_grau_instrucao NOT IN (SELECT ds_grau FROM dw.dim_escolaridade)
      UNION SELECT DISTINCT ds_grau_instrucao FROM tse.candidatos
      WHERE ds_grau_instrucao NOT IN (SELECT ds_grau FROM dw.dim_escolaridade) AND ds_grau_instrucao IS NOT NULL;

    INSERT INTO dw.dim_cargo (ds_cargo)
      SELECT DISTINCT ds_cargo FROM tse.candidatos
      WHERE ds_cargo NOT IN (SELECT ds_cargo FROM dw.dim_cargo);

    INSERT INTO dw.dim_partido (sg_partido)
      SELECT DISTINCT sg_partido FROM tse.candidatos
      WHERE sg_partido NOT IN (SELECT sg_partido FROM dw.dim_partido) AND sg_partido IS NOT NULL;

    DELETE FROM dw.fato_eleitorado;
    INSERT INTO dw.fato_eleitorado (sk_municipio, sk_genero, sk_raca, sk_esc, qtd_eleitores)
    SELECT dm.sk_municipio, g.sk_genero, r.sk_raca, e.sk_esc, SUM(t.qtd)
    FROM tse.eleitorado t
    JOIN dw.dim_municipio dm ON dm.nome = t.nm_municipio
    JOIN dw.dim_genero g ON g.ds_genero = t.ds_genero
    JOIN dw.dim_raca_cor r ON r.ds_raca_cor = t.ds_raca_cor
    JOIN dw.dim_escolaridade e ON e.ds_grau = t.ds_grau_instrucao
    GROUP BY dm.sk_municipio, g.sk_genero, r.sk_raca, e.sk_esc;

    DELETE FROM dw.fato_eleitos;
    INSERT INTO dw.fato_eleitos (sk_municipio, sk_genero, sk_raca, sk_esc, sk_cargo, sk_partido, flag_novato_estrito, flag_sem_mandato)
    SELECT dm.sk_municipio, g.sk_genero, r.sk_raca, e.sk_esc, ca.sk_cargo, p.sk_partido,
      CASE WHEN h.nr_cpf IS NULL THEN 1 ELSE 0 END,
      CASE WHEN c.ds_ocupacao NOT IN ('VEREADOR','PREFEITO','DEPUTADO ESTADUAL','DEPUTADO FEDERAL','SENADOR') THEN 1 ELSE 0 END
    FROM tse.candidatos c
    JOIN dw.dim_municipio dm ON dm.nome = c.nm_ue
    JOIN dw.dim_genero g ON g.ds_genero = c.ds_genero
    JOIN dw.dim_raca_cor r ON r.ds_raca_cor = c.ds_cor_raca
    JOIN dw.dim_escolaridade e ON e.ds_grau = c.ds_grau_instrucao
    JOIN dw.dim_cargo ca ON ca.ds_cargo = c.ds_cargo
    JOIN dw.dim_partido p ON p.sg_partido = c.sg_partido
    LEFT JOIN tse.candidatos_hist h ON h.nr_cpf = c.nr_cpf
    WHERE c.ds_sit_tot_turno LIKE 'ELEITO%' AND c.ds_cargo IN ('PREFEITO','VEREADOR');
END;
GO

/* ---------- 5) Checagem rápida ---------- */
SELECT * FROM ibge.municipios ORDER BY nome;
GO
SELECT name AS view_kpi FROM sys.views WHERE schema_id = SCHEMA_ID('bi');
GO
