# Banco de Dados — CirinosData

## Onde está

- **Servidor:** `.\SQLEXPRESS` (SQL Server 2025 Express, autenticação Windows)
- **Database:** `CirinosData`
- **Conexão:** `sqlcmd -S ".\SQLEXPRESS" -E -C` (sempre com `-f 65001` ao rodar scripts `.sql` — ver Encoding)

## Fonte dos dados

- **TSE Dados Abertos, Eleições Municipais 2024** (download manual via navegador; a API bloqueia robôs com 403):
  - `data/tse/raw/perfil_eleitorado_2024/perfil_eleitorado_2024_{MA,PI,CE,RN,PB,PE,AL,SE,BA}.csv` — perfil do eleitorado por seção (9 UFs do NE)
  - `data/tse/raw/consulta_cand_2024/consulta_cand_2024_{MA,PI,CE,RN,PB,PE,AL,SE,BA}.csv` — candidaturas 2024 (9 UFs do NE)
- **IBGE/SIDRA, Censo 2022** (Tabela 9514, var. 93): população das 9 capitais, já embutida no script-base.
- Escopo carregado: **9 capitais do NE** (São Luís, Teresina, Fortaleza, Natal, João Pessoa, Recife, Maceió, Aracaju, Salvador).

## Estrutura (schemas)

| Schema | Papel |
|---|---|
| `ibge` | Base populacional das capitais |
| `tse` | Staging dos dados reais do TSE, já filtrados p/ as 9 capitais |
| `bi` | Views de apoio (KPI1–3) |
| `dw` | Star schema auxiliar (dimensões + fatos), populado via procedure |

### `ibge.municipios` (9 linhas)

| Coluna | Tipo | Obs. |
|---|---|---|
| `cod_ibge` | INT PK | ex. 2111300 (São Luís) |
| `nome` | VARCHAR(100) | nome canônico com acentos |
| `uf` | CHAR(2) | |
| `regiao` | CHAR(2) | sempre `'NE'` |
| `eh_capital` | BIT | sempre 1 |
| `pop_2022` | INT | Censo 2022 (SIDRA) |

### `tse.eleitorado` (852 linhas · 8.484.617 eleitores)

Agregado por grupo demográfico (não é 1 linha por eleitor).

| Coluna | Tipo | Obs. |
|---|---|---|
| `id` | INT IDENTITY PK | |
| `sg_uf` | VARCHAR(2) | |
| `nm_municipio` | VARCHAR(100) | igual a `ibge.municipios.nome` (JOIN por nome) |
| `ds_genero` | VARCHAR(20) | `FEMININO` / `MASCULINO` |
| `ds_raca_cor` | VARCHAR(30) | `PRETA`, `PARDA`, `BRANCA`, `AMARELA`, `INDIGENA`, `NAO INFORMADO`… |
| `ds_grau_instrucao` | VARCHAR(50) | valores reais: `SUPERIOR COMPLETO`, `SUPERIOR INCOMPLETO`, `ENSINO MÉDIO COMPLETO`… (sem prefixo `ENSINO` no superior) |
| `qtd` | INT | nº de eleitores do grupo |

### `tse.candidatos` (4.444 linhas · 285 eleitos pref+ver)

Todas as candidaturas das 9 capitais em 2024 (todos os cargos e situações).

| Coluna | Tipo | Obs. |
|---|---|---|
| `id` | INT IDENTITY PK | |
| `sg_uf` | VARCHAR(2) | |
| `nm_ue` | VARCHAR(100) | município; igual a `ibge.municipios.nome` (JOIN por nome) |
| `ds_cargo` | VARCHAR(30) | `PREFEITO`, `VEREADOR`, `VICE-PREFEITO` |
| `ds_sit_tot_turno` | VARCHAR(30) | **atenção:** vereador eleito = `ELEITO POR QP` / `ELEITO POR MÉDIA`; só prefeito é `ELEITO` puro. Filtrar com `LIKE 'ELEITO%'` |
| `ds_genero` | VARCHAR(20) | |
| `ds_cor_raca` | VARCHAR(30) | (no candidato o campo chama `DS_COR_RACA`) |
| `ds_grau_instrucao` | VARCHAR(50) | `SUPERIOR COMPLETO` (sem `ENSINO`) e demais |
| `nr_cpf` | VARCHAR(14) | **100% mascarado (`-4`, LGPD) — não serve como chave** |
| `ds_ocupacao` | VARCHAR(100) | base da renovação ampla (ex. `VEREADOR`, `ADVOGADO`…) |
| `sg_partido` | VARCHAR(20) | base do porte partidário (contar eleitos por partido) |
| `nr_titulo` | — | **não carregado**; existe no CSV bruto como `NR_TITULO_ELEITORAL_CANDIDATO` (100% preenchido) — é a chave viável p/ cruzar com 2020/2016 se um dia precisar |

### `tse.candidatos_hist` (vazia)

Reservada ao cruzamento histórico (KPI3 estrita). Sem as bases 2020/2016, está vazia e a coluna estrita dos views retorna NULL.

### `bi.vw_KPI1_Gap`, `bi.vw_KPI2_Escolaridade`, `bi.vw_KPI3_Renovacao`

Views de apoio por capital (JOIN com `ibge.municipios` pelo nome). Correções já aplicadas aos valores reais: `LIKE 'ELEITO%'`, `SUPERIOR COMPLETO` nos dois lados, `taxa_estrita = NULL` sem hist.

### `dw.*` + `dw.sp_carga_dw`

`dim_municipio` (9), `dim_genero`, `dim_raca_cor`, `dim_escolaridade`, `dim_cargo`, `dim_partido`, `fato_eleitorado` (852), `fato_eleitos` (285). Recarrega com `EXEC dw.sp_carga_dw;` (limpa e reinsere fatos).

## Pipeline de carga (ordem)

```powershell
sqlcmd -S ".\SQLEXPRESS" -E -C -f 65001 -i CirinosData_TSE_NE.sql
python scripts\build_ne_fast.py        # raw -> data\tse\clean\*.csv (só 9 UFs, só capitais)
python scripts\gen_inserts.py          # clean -> scripts\carga_real_inserts.sql (INSERTs Unicode)
sqlcmd -S ".\SQLEXPRESS" -E -C -f 65001 -i scripts\carga_real_inserts.sql
sqlcmd -S ".\SQLEXPRESS" -E -C -Q "USE CirinosData; EXEC dw.sp_carga_dw;"
```

Scripts auxiliares: `scripts\preparar_tse_para_bulk.py` (genérico), `scripts\gerar_massa_sintetica.py` (massa fake p/ dev — **não** está no banco), `scripts\fix_views_reais.sql`, `scripts\fix_nomes.sql`, `scripts\fix_encoding_sql.py`.

## Encoding (importante)

- Collation do banco: `SQL_Latin1_General_CP1_CI_AS` (CP1252 — cobre todos os acentos PT em `VARCHAR`).
- Regras: arquivos `.sql` em **UTF-8 com BOM**, carga com **literais `N''`** e sqlcmd **sempre com `-f 65001`**. Sem isso, `São Luís / João Pessoa / Maceió` viram mojibake e os JOINs por nome quebram (foi o que aconteceu e foi corrigido).
- Display estranho no console (`Macei�`) é só codepage do terminal — o dado armazenado está correto (validado com `WHERE nome IN (N'…')` = 9/9 nas 3 tabelas).

## Limitações conhecidas

- `BULK INSERT` (`scripts\carga_tse_bulk.sql`) falha lendo do OneDrive (conta de serviço do SQL sem acesso → `IID_IColumnsInfo`); a carga canônica é via `carga_real_inserts.sql`. BULK funciona de pasta local (testado via `%TEMP%`).
- Arquivo de hist vazio (só header) também quebra BULK — bloco comentado/documentado no script.
- `votacao_candidato_munzona_2024.zip` baixado mas não usado (o `consulta_cand` já traz eleitos + atributos).
