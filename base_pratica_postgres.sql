-- =====================================================================
--  BASE DE PRÁTICA - SQL INTERMEDIÁRIO (Módulo 1 · Semana 10)
--  Compatível com PostgreSQL 13+ (usa funções de janela e GENERATE_SERIES;
--  qualquer versão razoavelmente recente funciona).
--
--  COMO USAR
--    Linha de comando (psql): psql -U seu_usuario -f base_pratica_postgres.sql
--    O script usa o comando \c para trocar de banco no meio do arquivo;
--    isso só funciona no psql. Pelo pgAdmin, rode em duas etapas:
--      1) Abra uma conexão em qualquer banco (ex.: postgres) e execute
--         só o bloco "ETAPA 1" abaixo.
--      2) Abra uma NOVA conexão já apontando para o banco pratica_sql
--         (crie-a na árvore de conexões do pgAdmin) e execute o
--         restante do arquivo ("ETAPA 2" em diante) nessa conexão.
--
--  O script é DETERMINÍSTICO: não usa RANDOM(). Todos os alunos obtêm
--  exatamente os mesmos dados e, portanto, os mesmos resultados.
--
--  Data de referência da base: 30/09/2025 (não use CURRENT_DATE nas
--  atividades; use DATE '2025-09-30' para que os resultados sejam iguais).
--
--  PROBLEMAS PLANTADOS DE PROPÓSITO (fazem parte das atividades):
--    - passageiros.email com maiúsculas e espaços nas pontas
--    - transacoes.valor com NULL
--    - transacoes.cliente_id que não existe em clientes ("órfãs")
--    - clientes que nunca compraram
--    - motoristas.nota com NULL
--    - 5 pares de transações do mesmo cliente com o mesmo valor
--    - motoristas com volumes de corridas bem diferentes entre si
-- =====================================================================

-- ---------------------------------------------------------------------
--  ETAPA 1 - criação do banco (rode conectado a qualquer banco, ex.: postgres)
-- ---------------------------------------------------------------------
DROP DATABASE IF EXISTS pratica_sql;
CREATE DATABASE pratica_sql ENCODING 'UTF8';

\c pratica_sql

-- ---------------------------------------------------------------------
--  ETAPA 2 - ESTRUTURA
--  Obs.: transacoes.cliente_id NÃO tem FOREIGN KEY de propósito, para
--  que existam transações órfãs (problema de qualidade de dados).
-- ---------------------------------------------------------------------
CREATE TABLE clientes (
  id             INT PRIMARY KEY,
  nome           VARCHAR(80)  NOT NULL,
  email          VARCHAR(120) NOT NULL,
  segmento       VARCHAR(20)  NOT NULL,
  data_cadastro  DATE         NOT NULL
);

CREATE TABLE transacoes (
  id          INT PRIMARY KEY,
  cliente_id  INT NOT NULL,
  data        DATE NOT NULL,
  valor       NUMERIC(10,2) NULL,
  status      VARCHAR(15) NOT NULL
);

CREATE TABLE itens_transacao (
  id             INT PRIMARY KEY,
  transacao_id   INT NOT NULL,
  produto        VARCHAR(40) NOT NULL,
  quantidade     INT NOT NULL,
  preco_unitario NUMERIC(10,2) NOT NULL,
  FOREIGN KEY (transacao_id) REFERENCES transacoes(id)
);

CREATE TABLE passageiros (
  id             INT PRIMARY KEY,
  nome           VARCHAR(80)  NOT NULL,
  email          VARCHAR(120) NOT NULL,
  telefone       VARCHAR(20)  NOT NULL,
  data_cadastro  DATE         NOT NULL
);

CREATE TABLE motoristas (
  id             INT PRIMARY KEY,
  nome           VARCHAR(80) NOT NULL,
  data_cadastro  DATE        NOT NULL,
  nota           NUMERIC(3,2) NULL
);

CREATE TABLE corridas (
  id             INT PRIMARY KEY,
  passageiro_id  INT NOT NULL,
  motorista_id   INT NOT NULL,
  data_hora      TIMESTAMP NOT NULL,
  valor          NUMERIC(8,2) NOT NULL,
  FOREIGN KEY (passageiro_id) REFERENCES passageiros(id),
  FOREIGN KEY (motorista_id)  REFERENCES motoristas(id)
);

-- ---------------------------------------------------------------------
--  ETAPA 3 - CARGA DE DADOS
--  Observação técnica (só para quem for adaptar o script): o PostgreSQL
--  faz divisão inteira quando os dois lados de "/" são inteiros, ao
--  contrário do MySQL, que sempre devolve decimal. Por isso, sempre que
--  o resultado precisa ter casas decimais, um dos lados é escrito como
--  decimal explicitamente (ex.: "/ 100.0" em vez de "/ 100").
-- ---------------------------------------------------------------------

-- CLIENTES: 200 linhas (ids 1..200).
-- Os ids 191..200 nunca aparecem em transacoes (clientes sem compra).
INSERT INTO clientes (id, nome, email, segmento, data_cadastro)
SELECT
  i,
  'Cliente ' || LPAD(i::text, 3, '0'),
  'cliente' || i || '@' ||
    (ARRAY['gmail.com','outlook.com','empresa.com.br','yahoo.com'])[1 + MOD(i, 4)],
  (ARRAY['Varejo','Premium','Corporate','Startup'])[1 + MOD(i, 4)],
  DATE '2023-01-01' + MOD(i * 7, 700)
FROM generate_series(1, 200) AS i;

-- TRANSACOES: 1200 linhas.
--  - a cada 60 transações, uma tem cliente_id inexistente (9001)
--  - a cada 50 transações, uma tem valor NULL
--  - datas entre 01/01/2024 e 30/09/2025
--  - status: 60% concluida, 20% pendente, 10% cancelada, 10% estornada
INSERT INTO transacoes (id, cliente_id, data, valor, status)
SELECT
  i,
  CASE WHEN MOD(i, 60) = 0 THEN 9001
       ELSE 1 + MOD(i * 13, 190) END,
  DATE '2024-01-01' + MOD(i * 11, 639),
  CASE WHEN MOD(i, 50) = 7 THEN NULL
       ELSE ROUND(20 + MOD(i * 37, 481) + MOD(i, 100) / 100.0, 2) END,
  (ARRAY['concluida','concluida','concluida','concluida','concluida',
         'concluida','pendente','pendente','cancelada','estornada'])[1 + MOD(i, 10)]
FROM generate_series(1, 1200) AS i;

-- Plantio: 5 pares de transações do MESMO cliente com o MESMO valor
-- (ids 390..394 copiam o valor de 200..204, que são do mesmo cliente).
-- Servem para mostrar que UNION apaga linhas legítimas repetidas.
UPDATE transacoes t
SET    valor = o.valor
FROM   transacoes o
WHERE  o.id = t.id - 190
  AND  t.id BETWEEN 390 AND 394;

-- ITENS_TRANSACAO: 1 a 3 itens por transação, para as transações 1..400
-- (usada na atividade que mostra o "fan-out" do JOIN 1:N).
INSERT INTO itens_transacao (id, transacao_id, produto, quantidade, preco_unitario)
SELECT
  (n.i - 1) * 3 + k.j,
  n.i,
  (ARRAY['Plano Basico','Plano Plus','Suporte','Consultoria','Treinamento'])[1 + MOD(n.i + k.j, 5)],
  1 + MOD(n.i * k.j, 3),
  ROUND((10 + MOD(n.i * 7 + k.j * 13, 90))::numeric, 2)
FROM   generate_series(1, 400) AS n(i)
JOIN   generate_series(1, 3)   AS k(j) ON k.j <= 1 + MOD(n.i, 3);

-- PASSAGEIROS: 150 linhas.
-- E-mails "sujos": todo id múltiplo de 4 está em MAIÚSCULAS, todo
-- múltiplo de 6 tem espaços nas pontas e todo múltiplo de 10 tem a
-- primeira letra maiúscula. A distribuição por provedor é desigual de
-- propósito (gmail.com concentra mais passageiros que os demais).
INSERT INTO passageiros (id, nome, email, telefone, data_cadastro)
WITH base AS (
  SELECT
    i,
    'passageiro' || i || '@' ||
      (ARRAY['gmail.com','hotmail.com','outlook.com','yahoo.com.br','uol.com.br'])
        [1 + FLOOR(5 * POWER(MOD(i * 37, 151) / 151.0, 1.7))::int] AS em
  FROM generate_series(1, 150) AS i
)
SELECT
  i,
  'Passageiro ' || LPAD(i::text, 3, '0'),
  CASE
    WHEN MOD(i, 4) = 0  THEN UPPER(em)
    WHEN MOD(i, 6) = 0  THEN '  ' || em || ' '
    WHEN MOD(i, 10) = 0 THEN UPPER(LEFT(em, 1)) || SUBSTRING(em FROM 2)
    ELSE em
  END,
  '(21) 9' || LPAD(MOD(i * 7919, 10000)::text, 4, '0') || '-' || LPAD(MOD(i * 104729, 10000)::text, 4, '0'),
  DATE '2023-06-01' + MOD(i * 5, 600)
FROM base;

-- MOTORISTAS: 40 linhas (nota NULL a cada 9 ids).
INSERT INTO motoristas (id, nome, data_cadastro, nota)
SELECT
  i,
  'Motorista ' || LPAD(i::text, 2, '0'),
  DATE '2019-01-01' + MOD(i * 97, 2400),
  CASE WHEN MOD(i, 9) = 0 THEN NULL
       ELSE ROUND(3.5 + MOD(i * 7, 15) / 10.0, 2) END
FROM generate_series(1, 40) AS i;

-- CORRIDAS: 3000 linhas.
-- Os motoristas de id baixo recebem bem mais corridas que os de id alto
-- (distribuição assimétrica, útil para "acima da média").
INSERT INTO corridas (id, passageiro_id, motorista_id, data_hora, valor)
SELECT
  i,
  1 + MOD(i * 17, 150),
  1 + FLOOR(40 * POWER(MOD(i * 7919, 10007) / 10007.0, 1.6))::int,
  TIMESTAMP '2024-01-01 00:00:00' + MOD(i * 7919, 639 * 24 * 60) * INTERVAL '1 minute',
  ROUND(8 + MOD(i * 53, 1400) / 10.0 + MOD(i, 10) * 0.5, 2)
FROM generate_series(1, 3000) AS i;

-- ---------------------------------------------------------------------
--  ETAPA 4 - CONFERÊNCIA FINAL: compare com a tabela do caderno
-- ---------------------------------------------------------------------
SELECT 'clientes'        AS tabela, COUNT(*) AS linhas FROM clientes
UNION ALL SELECT 'transacoes',      COUNT(*) FROM transacoes
UNION ALL SELECT 'itens_transacao', COUNT(*) FROM itens_transacao
UNION ALL SELECT 'passageiros',     COUNT(*) FROM passageiros
UNION ALL SELECT 'motoristas',      COUNT(*) FROM motoristas
UNION ALL SELECT 'corridas',        COUNT(*) FROM corridas;
