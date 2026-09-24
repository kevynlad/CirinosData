/* ENCODING: arquivo em UTF-8 com BOM. Rodar sempre com sqlcmd usando -C -f 65001 (ex.: sqlcmd -S SQLEXPRESS -E -C -f 65001 -i arquivo.sql) para nao gerar mojibake em Sao Luis / Joao Pessoa / Maceio. */
USE CirinosData;
GO
UPDATE ibge.municipios SET nome = N'São Luís' WHERE cod_ibge = 2111300;
UPDATE ibge.municipios SET nome = N'João Pessoa' WHERE cod_ibge = 2507507;
UPDATE ibge.municipios SET nome = N'Maceió' WHERE cod_ibge = 2704302;
GO
SELECT cod_ibge, nome FROM ibge.municipios ORDER BY nome;
GO
