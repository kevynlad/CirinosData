# Respostas KPIs — Capitais do Nordeste (CirinosData)

**Cliente:** Diretórios Partidários Regionais e Consultorias de Inteligência Eleitoral do Nordeste
**Escopo:** 9 capitais do Nordeste | Eleições Municipais 2024 (TSE) + Censo Demográfico 2022 (IBGE)
**Data:** 24/09/2026
**Origem:** Matriz `CirinosData - Matriz Requisitos KPIs TSE - Inicial.docx.md`

> Este arquivo responde aos 3 KPIs da matriz, com fórmula, fonte/API, query T-SQL e tabela-base já preenchida com dados reais do IBGE. Os dados do TSE exigem download manual via navegador (a API bloqueia robôs com 403/Akamai — ver seção 5).

---

## 1. Base demográfica confirmada via API IBGE (real, testado em 24/09/2026)

Fontes testadas e funcionando:
- Detalhe do município: `GET https://servicodados.ibge.gov.br/api/v1/localidades/municipios/{codIBGE}`
- População residente Censo 2022: `GET https://apisidra.ibge.gov.br/values/t/9514/n6/{codIBGE}/v/93/p/last%201`
  - Tabela 9514, Variável 93 = População residente, Ano 2022, Total (sexo/idade = Total)

| Capital | UF | codIBGE (correto) | Pop. residente Censo 2022 (IBGE/SIDRA) |
|---|---|---|---|
| São Luís | MA | 2111300 | 1.037.775 |
| Teresina | PI | 2211001 | 866.300 |
| Fortaleza | CE | 2304400 | 2.428.708 |
| Natal | RN | 2408102 | 751.300 |
| João Pessoa | PB | 2507507 | 833.932 |
| Recife | PE | 2611606 | 1.488.920 |
| Maceió | AL | 2704302 | 957.916 |
| Aracaju | SE | 2800308 | 602.757 |
| Salvador | BA | 2927408 | 2.417.678 |

> Atenção: Teresina é **2211001** (2205401 retorna `[]` e quebra o script).

Script Python testado (IBGE — funciona):
```python
import requests
caps = [2111300,2211001,2304400,2408102,2507507,2611606,2704302,2800308,2927408]
for c in caps:
    mun = requests.get(f'https://servicodados.ibge.gov.br/api/v1/localidades/municipios/{c}', timeout=20).json()
    pop = requests.get(f'https://apisidra.ibge.gov.br/values/t/9514/n6/{c}/v/93/p/last%201', timeout=30).json()
    print(mun['nome'], pop[1]['V'])
```

---

## 2. KPI 1 — Gap de Representatividade (gênero e raça/cor)

**Responde às Perguntas 1 e 5:**
- P1: composição de câmaras/prefeituras espelha a pirâmide sociodemográfica do eleitorado?
- P5: composição de vereadores/prefeitos espelha gênero e raça/cor do eleitorado?

**Definição / Fórmula (da matriz):**
```
Gap_pp = (% do grupo no eleitorado) - (% do grupo entre os eleitos)
Gap_relativo_% = Gap_pp / (% do grupo no eleitorado) * 100
```
Positivo = sub-representação entre eleitos. Negativo = sobrerrepresentação.

Recortes obrigatórios: `Município × Gênero (F/M)`, `Município × Raça/Cor (Preta, Parda, Branca, Indígena, Amarela)`.

**Fontes:**
- Eleitorado: Portal de Dados Abertos TSE → `Eleitorado 2024` → `Perfil do eleitorado por seção eleitoral - {UF}` (CSV por UF, filtrar `CD_MUNICIPIO_TSE` das capitais + `DS_GENERO`, `DS_RACA_COR`).
- Eleitos: Portal de Dados Abertos TSE → `Resultados 2024` → `votacao_candidato_munzona_2024` ou `consulta_cand_2024` (filtrar `SG_UE` das capitais, `DS_CARGO` = PREFEITO/VEREADOR, `DS_SIT_TOT_TURNO` = ELEITO). Campos `DS_GENERO`, `DS_COR_RACA`.

**T-SQL de referência (após importar CSVs para `tse.eleitorado_2024` e `tse.candidatos_2024`):**
```sql
-- % grupo no eleitorado por capital
WITH ele AS (
  SELECT SG_UF, NM_MUNICIPIO,
    COUNT(*) AS total_eleitores,
    SUM(CASE WHEN DS_GENERO='FEMININO' THEN 1 ELSE 0 END)*1.0/COUNT(*) AS pct_F_eleit,
    SUM(CASE WHEN DS_RACA_COR IN ('PRETA','PARDA') THEN 1 ELSE 0 END)*1.0/COUNT(*) AS pct_negros_eleit
  FROM tse.eleitorado_2024
  WHERE NM_MUNICIPIO IN ('SÃO LUÍS','TERESINA','FORTALEZA','NATAL','JOÃO PESSOA','RECIFE','MACEIÓ','ARACAJU','SALVADOR')
  GROUP BY SG_UF, NM_MUNICIPIO
),
eleitos AS (
  SELECT SG_UF, NM_UE AS NM_MUNICIPIO,
    COUNT(*) AS total_eleitos,
    SUM(CASE WHEN DS_GENERO='FEMININO' THEN 1 ELSE 0 END)*1.0/COUNT(*) AS pct_F_eleitos,
    SUM(CASE WHEN DS_COR_RACA IN ('PRETA','PARDA') THEN 1 ELSE 0 END)*1.0/COUNT(*) AS pct_negros_eleitos
  FROM tse.candidatos_2024
  WHERE DS_SIT_TOT_TURNO='ELEITO'
    AND DS_CARGO IN ('PREFEITO','VEREADOR')
  GROUP BY SG_UF, NM_UE
)
SELECT e.NM_MUNICIPIO,
  ROUND((e.pct_F_eleit - t.pct_F_eleitos)*100,2) AS gap_pp_mulheres,
  ROUND((e.pct_negros_eleit - t.pct_negros_eleitos)*100,2) AS gap_pp_negros
FROM ele e JOIN eleitos t ON e.NM_MUNICIPIO=t.NM_MUNICIPIO;
```

**Resposta atual:**
> Status: **PENDENTE DE CARGA TSE** — base IBGE pronta, cálculo bloqueado sem os CSVs do TSE. Após carga, preencher tabela abaixo. Decisão apoiada: direcionar incentivos/recursos para grupos sub-representados nos municípios com maior `gap_pp`.

| Capital | % mulheres eleitorado | % mulheres eleitas | Gap mulheres (pp) | % negros eleitorado | % negros eleitos | Gap negros (pp) |
|---|---|---|---|---|---|---|
| São Luís | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ |
| Teresina | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ |
| Fortaleza | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ |
| Natal | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ |
| João Pessoa | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ |
| Recife | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ |
| Maceió | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ |
| Aracaju | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ |
| Salvador | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ | _preencher_ |

---

## 3. KPI 2 — Índice de Sobrerrepresentação por Escolaridade

**Responde às Perguntas 2 e 4:**
- P2: distorção entre escolaridade dos eleitos e do eleitorado (capitais × interior)?
- P4: renovação tem mais sucesso entre quem tem ensino superior?

**Definição / Fórmula:**
```
Indice = (% eleitos com ENSINO SUPERIOR COMPLETO) / (% eleitores com ENSINO SUPERIOR COMPLETO)
```
= 1.0 → proporcional. > 1.0 → elite educacional sobrerrepresentada. Ex.: 4.5 = eleitos têm 4,5× mais superior que o eleitorado.

**Fontes:** mesmos arquivos do KPI 1, campos `DS_GRAU_INSTRUCAO` (eleitorado e candidatos).

**T-SQL:**
```sql
WITH a AS (
  SELECT NM_MUNICIPIO,
    SUM(CASE WHEN DS_GRAU_INSTRUCAO='ENSINO SUPERIOR COMPLETO' THEN 1 ELSE 0 END)*1.0/COUNT(*) AS pct_sup_eleit
  FROM tse.eleitorado_2024 GROUP BY NM_MUNICIPIO
),
b AS (
  SELECT NM_UE AS NM_MUNICIPIO,
    SUM(CASE WHEN DS_GRAU_INSTRUCAO='SUPERIOR COMPLETO' THEN 1 ELSE 0 END)*1.0/COUNT(*) AS pct_sup_eleitos
  FROM tse.candidatos_2024 WHERE DS_SIT_TOT_TURNO='ELEITO' GROUP BY NM_UE
)
SELECT a.NM_MUNICIPIO,
  ROUND(a.pct_sup_eleit*100,2) AS pct_sup_eleitorado,
  ROUND(b.pct_sup_eleitos*100,2) AS pct_sup_eleitos,
  ROUND(b.pct_sup_eleitos/NULLIF(a.pct_sup_eleit,0),2) AS indice_sobrerrep
FROM a JOIN b ON a.NM_MUNICIPIO=b.NM_MUNICIPIO;
```

**Resposta atual:**
> Status: **PENDENTE DE CARGA TSE**. Hipótese a testar (P2/P4): índice >> 1 nas 9 capitais. Decisão apoiada: adaptar linguagem/porta-vozes e orientar comitês sobre viabilidade por perfil educacional.

| Capital | % eleitores c/ superior | % eleitos c/ superior | Índice |
|---|---|---|---|
| (9 capitais) | _preencher_ | _preencher_ | _preencher_ |

---

## 4. KPI 3 — Taxa de Sucesso de Renovação Política ⚠️ *precisa refino (feedback 25/08/2026)*

**Responde às Perguntas 3, 4 e 5.** Ajuste sugerido pelo grupo revisor: refinar para “candidato sem nenhuma candidatura anterior” (não só sem mandato prévio).

**Definição atual (matriz):**
```
Taxa_renovacao = (eleitos sem mandato prévio) / (total de eleitos) * 100
```

**Definição refinada proposta (para aceite do revisor):**
```
Taxa_renovacao_estrita = (eleitos que NUNCA foram candidatos antes de 2024) / (total de eleitos) * 100
Taxa_renovacao_ampla   = (eleitos sem mandato prévio, mesmo se já candidataram) / (total de eleitos) * 100
```
Manter as duas colunas e comparar por `PORTE_PARTIDO` (grande/médio/pequeno por nº de eleitos no NE) e por `ESCOLARIDADE`.

**Fontes:** `consulta_cand_2024` + histórico `consulta_cand_2020/2016` (mesmo `NR_CPF`/`NM_URNA` nunca apareceu antes = novato estrito). Porte do partido via total de eleitos por `SG_PARTIDO`.

**T-SQL:**
```sql
-- Classifica novato estrito via LEFT JOIN com histórico
WITH hist AS (SELECT DISTINCT NR_CPF FROM tse.candidatos_2020 UNION SELECT DISTINCT NR_CPF FROM tse.candidatos_2016),
base AS (
  SELECT c.NM_UE, c.SG_PARTIDO, c.DS_GRAU_INSTRUCAO,
    CASE WHEN h.NR_CPF IS NULL THEN 1 ELSE 0 END AS eh_novato_estrito,
    CASE WHEN c.DS_OCUPACAO NOT IN ('VEREADOR','PREFEITO','DEPUTADO','SENADOR') THEN 1 ELSE 0 END AS sem_mandato_previo
  FROM tse.candidatos_2024 c LEFT JOIN hist h ON h.NR_CPF=c.NR_CPF
  WHERE c.DS_SIT_TOT_TURNO='ELEITO'
)
SELECT NM_UE AS capital,
  COUNT(*) AS total_eleitos,
  ROUND(SUM(sem_mandato_previo)*100.0/COUNT(*),2) AS taxa_ampla,
  ROUND(SUM(eh_novato_estrito)*100.0/COUNT(*),2) AS taxa_estrita
FROM base GROUP BY NM_UE;
```

**Resposta atual:**
> Status: **PENDENTE + EM REFINO**. Decisão apoiada: redefinir aposta em novatos vs. reeleição por cidade/porte partidário. Entregar as duas taxas (ampla + estrita) para fechar o feedback.

| Capital | Total eleitos (pref+ver) | Taxa ampla (%) | Taxa estrita — sem candidatura anterior (%) |
|---|---|---|---|
| (9 capitais) | _preencher_ | _preencher_ | _preencher_ |

---

## 5. Como obter os dados do TSE (obrigatório — API bloqueia script)

Testado em 24/09/2026: `dadosabertos.tse.jus.br/api/*`, `cdn.tse.jus.br/*` e `divulgacandcontas.tse.jus.br/*` retornam **403 Access Denied (Akamai/EdgeSuite)** para scripts Python/requests. O `resultados.tse.jus.br/oficial/ele2024` só ficou no ar em out–nov/2024 (fora do ar agora).

**Passo manual (5 min, via navegador):**
1. Acesse `https://dadosabertos.tse.jus.br/dataset/eleitorado-2024` → baixe `Perfil do eleitorado por seção` das 9 UFs (MA, PI, CE, RN, PB, PE, AL, SE, BA) — ZIP/CSV.
2. Acesse `https://dadosabertos.tse.jus.br/dataset/resultados-2024` → baixe `votacao_candidato_munzona` + `consulta_cand_2024`.
3. Salve em `./data/tse/` e rode o script de carga para SQL Server (a equipe fornece `bulk insert`), depois as queries das seções 2–4.
4. Filtre sempre pelas 9 capitais (usar `CD_MUNICIPIO_IBGE` acima para conferência; o TSE usa `CD_MUNICIPIO` próprio + `NM_MUNICIPIO` — conferir pelo nome).

Não inventar números: sem esses CSVs os gaps/índices/taxas não podem ser calculados com validade para a banca.

---

## 6. Mapeamento Perguntas × KPIs × Decisões (resumo executivo)

| Pergunta | KPI que responde | Decisão |
|---|---|---|
| 1 — Câmaras/prefeituras espelham pirâmide do eleitorado? | KPI 1 (Gap) | Incentivos/recursos p/ sub-representados |
| 2 — Distorção escolaridade eleitos × eleitorado? | KPI 2 (Índice) | Linguagem, porta-vozes, formação |
| 3 — Taxa renovação × porte partidário? | KPI 3 (Renovação) | Aposta novatos vs. reeleição/alianças |
| 4 — Renovação maior entre superior? | KPI 2 + KPI 3 | Seleção de perfis com tração |
| 5 — Eleitos espelham gênero/raça por município? | KPI 1 (+ KPI 3) | Recrutamento nos maiores gaps |

**Próximo passo para fechar a entrega:** baixar os 2 conjuntos TSE, rodar as 3 queries e colar os resultados nas tabelas das seções 2–4. A base IBGE desta página já é a resposta demográfica oficial.
