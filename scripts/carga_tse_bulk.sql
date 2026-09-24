/* ============================================================
   CirinosData — Carga REAL TSE via BULK INSERT (SQL Server)
   Pré-requisito: rodar  python scripts\preparar_tse_para_bulk.py
   que gera data\tse\clean\*.csv
   Rodar: sqlcmd -S ".\SQLEXPRESS" -E -C -i scripts\carga_tse_bulk.sql
   ============================================================ */
USE CirinosData;
GO

TRUNCATE TABLE tse.eleitorado;
GO

BULK INSERT tse.eleitorado
FROM 'C:\Users\kevyn\OneDrive\Documentos\Cirinos Data\data\tse\clean\tse_eleitorado_clean.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);
GO

TRUNCATE TABLE tse.candidatos;
GO

BULK INSERT tse.candidatos
FROM 'C:\Users\kevyn\OneDrive\Documentos\Cirinos Data\data\tse\clean\tse_candidatos_clean.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);
GO

/* Hist opcional (KPI3 estrita). Se o arquivo não existir OU tiver só o header
   (sem linhas de dados), o BULK falha com IID_IColumnsInfo — nesse caso comente este bloco.
   NOTA: BULK INSERT lê pelo usuário de serviço do SQL Server, que pode não ter
   acesso a pastas do OneDrive (erro IID_IColumnsInfo). Alternativas que funcionam:
   1) copiar data\tse\clean\*.csv p/ uma pasta local (ex. %TEMP%\CirinosTSE) e ajustar os FROMs;
   2) usar scripts\carga_real_inserts.sql (INSERTs Unicode, canônico — rode com sqlcmd -C -f 65001). */
TRUNCATE TABLE tse.candidatos_hist;
GO

BULK INSERT tse.candidatos_hist
FROM 'C:\Users\kevyn\OneDrive\Documentos\Cirinos Data\data\tse\clean\tse_candidatos_hist_clean.csv'
WITH (
    FORMAT = 'CSV',
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);
GO

/* ---------- Verificação ---------- */
SELECT 'tse.eleitorado' AS tabela, COUNT(*) AS linhas, SUM(qtd) AS eleitores FROM tse.eleitorado
UNION ALL SELECT 'tse.candidatos', COUNT(*), NULL FROM tse.candidatos
UNION ALL SELECT 'tse.candidatos_hist', COUNT(*), NULL FROM tse.candidatos_hist;
GO

SELECT TOP 5 * FROM tse.eleitorado;
GO
SELECT TOP 5 sg_uf, nm_ue, ds_cargo, ds_sit_tot_turno, ds_genero, ds_cor_raca FROM tse.candidatos;
GO

SELECT * FROM bi.vw_KPI1_Gap ORDER BY capital;
GO
SELECT * FROM bi.vw_KPI2_Escolaridade ORDER BY capital;
GO
SELECT * FROM bi.vw_KPI3_Renovacao ORDER BY capital;
GO
