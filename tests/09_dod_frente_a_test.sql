-- =====================================================================
-- 09_dod_frente_a_test.sql
-- DoD Frente A — teste de ponta a ponta na camada SQL.
--
-- Cria um trabalhador novo (Dora Lemos, código 1099, empresa A)
-- e insere um mês sintético de picagens em UTC puro.
-- Portugal em Julho é UTC+1 (WEST); horários escolhidos sem ambiguidade
-- de transição DST (que ocorre às 01:00 UTC).
--
-- Cenário coberto:
--   Dia 2026-07-01 — turno único com intervalo a atravessar o meio-dia
--   Dia 2026-07-02 — dois turnos distintos no mesmo dia
--   Dia 2026-07-03 — anulação + correção manual
--   Dia 2026-07-04 — picagem com desvio dispositivo/servidor = 420 s
--
-- Testes:
--   T1 — vista_horas_dia: dia 1 → 28800 s trabalho + 3600 s pausa, 1 turno
--   T2 — vista_horas_dia: dia 2 → 28800 s trabalho, 2 turnos, sem pausa
--   T3 — sequencia_valida bloqueia entrada enquanto entrada viva existe
--   T4 — sequencia_valida aceita entrada após anulação (lookup exclui anuladas)
--   T5 — vista_horas_dia: dia 3 → 31500 s trabalho, 1 turno (anulada não conta)
--   T6 — vista_picagem.desvio_segundos = 420 na picagem com desvio injetado
--   T7 — vista_picagem.desvio_segundos = 0 nas picagens sem desvio
--
-- Corre dentro de uma transação e faz rollback no fim (não deixa dados).
-- =====================================================================
\set ON_ERROR_STOP on

begin;

-- =====================================================================
-- Setup: empresa e loja reutilizadas do seed (empresa A + loja A1).
-- Novo trabalhador Dora Lemos — código 1099 não existe no seed.
-- =====================================================================
insert into trabalhador (id, empresa_id, nome, codigo_pessoal, ativo) values
  ('d0900000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'Dora Lemos', '1099', true);

-- =====================================================================
-- Dia 1 (2026-07-01): turno único com intervalo a atravessar o meio-dia
--
-- UTC  → Lisboa (UTC+1)
--   07:00 → 08:00  entrada
--   11:00 → 12:00  inicio_intervalo
--   12:00 → 13:00  fim_intervalo
--   16:00 → 17:00  saida
--
-- Cálculo manual de trabalho (momento_dispositivo):
--   segmento 1: entrada 07:00 → ini_interv 11:00 = 4h = 14400 s
--   segmento 2: fim_interv 12:00 → saida 16:00   = 4h = 14400 s
--   total trabalho = 28800 s (8.00 h)
-- Cálculo manual de pausa:
--   ini_interv 11:00 → fim_interv 12:00 = 1h = 3600 s
-- Desvio: momento_dispositivo = momento_servidor → desvio_segundos = 0
-- =====================================================================
insert into verificacao
  (id, empresa_id, trabalhador_id, loja_id, momento_dispositivo, momento_servidor)
values
  ('d0910000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-01 07:00:00+00', '2026-07-01 07:00:00+00'),
  ('d0910000-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-01 11:00:00+00', '2026-07-01 11:00:00+00'),
  ('d0910000-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-01 12:00:00+00', '2026-07-01 12:00:00+00'),
  ('d0910000-0000-0000-0000-000000000004',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-01 16:00:00+00', '2026-07-01 16:00:00+00');

insert into picagem (empresa_id, verificacao_id, tipo) values
  ('11111111-1111-1111-1111-111111111111',
   'd0910000-0000-0000-0000-000000000001', 'entrada'),
  ('11111111-1111-1111-1111-111111111111',
   'd0910000-0000-0000-0000-000000000002', 'inicio_intervalo'),
  ('11111111-1111-1111-1111-111111111111',
   'd0910000-0000-0000-0000-000000000003', 'fim_intervalo'),
  ('11111111-1111-1111-1111-111111111111',
   'd0910000-0000-0000-0000-000000000004', 'saida');

-- =====================================================================
-- Dia 2 (2026-07-02): dois turnos distintos no mesmo dia
--
--   Turno A: entrada 06:00 UTC → saida 10:00 UTC = 4h = 14400 s
--   Turno B: entrada 14:00 UTC → saida 18:00 UTC = 4h = 14400 s
--
-- Total trabalho = 28800 s (8.00 h); pausa = 0 s; turnos = 2
-- =====================================================================
insert into verificacao
  (id, empresa_id, trabalhador_id, loja_id, momento_dispositivo, momento_servidor)
values
  ('d0920000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-02 06:00:00+00', '2026-07-02 06:00:00+00'),
  ('d0920000-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-02 10:00:00+00', '2026-07-02 10:00:00+00'),
  ('d0920000-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-02 14:00:00+00', '2026-07-02 14:00:00+00'),
  ('d0920000-0000-0000-0000-000000000004',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-02 18:00:00+00', '2026-07-02 18:00:00+00');

insert into picagem (empresa_id, verificacao_id, tipo) values
  ('11111111-1111-1111-1111-111111111111',
   'd0920000-0000-0000-0000-000000000001', 'entrada'),
  ('11111111-1111-1111-1111-111111111111',
   'd0920000-0000-0000-0000-000000000002', 'saida'),
  ('11111111-1111-1111-1111-111111111111',
   'd0920000-0000-0000-0000-000000000003', 'entrada'),
  ('11111111-1111-1111-1111-111111111111',
   'd0920000-0000-0000-0000-000000000004', 'saida');

-- TESTE 1 — dia 1: 8h trabalho, 1h pausa, turno único, fechado
do $$
declare r record;
begin
  select * into r
    from public.vista_horas_dia
   where trabalhador_id = 'd0900000-0000-0000-0000-000000000001'
     and dia = '2026-07-01';

  if r is null then
    raise exception 'FALHA T1: dia 2026-07-01 não aparece em vista_horas_dia';
  end if;
  if r.seg_trabalho <> 28800 then
    raise exception 'FALHA T1: trabalho esperado 28800 s, obtido % s', r.seg_trabalho;
  end if;
  if r.seg_pausa <> 3600 then
    raise exception 'FALHA T1: pausa esperada 3600 s, obtida % s', r.seg_pausa;
  end if;
  if r.turnos <> 1 then
    raise exception 'FALHA T1: esperado 1 turno, obtido %', r.turnos;
  end if;
  if not r.todos_fechados then
    raise exception 'FALHA T1: dia 1 devia estar fechado (tem saida)';
  end if;
  raise notice 'TESTE 1 (dia 1: 28800 s trabalho + 3600 s pausa, 1 turno): OK';
end $$;

-- TESTE 2 — dia 2: 8h trabalho, 2 turnos, sem pausa, fechado
do $$
declare r record;
begin
  select * into r
    from public.vista_horas_dia
   where trabalhador_id = 'd0900000-0000-0000-0000-000000000001'
     and dia = '2026-07-02';

  if r is null then
    raise exception 'FALHA T2: dia 2026-07-02 não aparece em vista_horas_dia';
  end if;
  if r.seg_trabalho <> 28800 then
    raise exception 'FALHA T2: trabalho esperado 28800 s, obtido % s', r.seg_trabalho;
  end if;
  if r.seg_pausa <> 0 then
    raise exception 'FALHA T2: pausa esperada 0 s, obtida % s', r.seg_pausa;
  end if;
  if r.turnos <> 2 then
    raise exception 'FALHA T2: esperados 2 turnos, obtido %', r.turnos;
  end if;
  if not r.todos_fechados then
    raise exception 'FALHA T2: dia 2 devia estar fechado (ambos os turnos têm saida)';
  end if;
  raise notice 'TESTE 2 (dia 2: 28800 s trabalho, 2 turnos, sem pausa): OK';
end $$;

-- =====================================================================
-- Dia 3 (2026-07-03): anulação + correção manual
--
-- 3a. Entrada às 07:00 UTC — vai ser anulada
-- =====================================================================
insert into verificacao
  (id, empresa_id, trabalhador_id, loja_id, momento_dispositivo, momento_servidor)
values
  ('d0930000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-03 07:00:00+00', '2026-07-03 07:00:00+00');

insert into picagem (empresa_id, verificacao_id, tipo) values
  ('11111111-1111-1111-1111-111111111111',
   'd0930000-0000-0000-0000-000000000001', 'entrada');

-- TESTE 3 — com a entrada das 07:00 viva, sequencia_valida rejeita nova entrada
do $$
begin
  if public.sequencia_valida(
       '11111111-1111-1111-1111-111111111111',
       'd0900000-0000-0000-0000-000000000001',
       'entrada',
       '2026-07-03 07:10:00+00')
  then
    raise exception 'FALHA T3: sequencia_valida aceitou entrada após entrada viva às 07:00';
  end if;
  raise notice 'TESTE 3 (entrada viva bloqueia nova entrada no mesmo dia): OK';
end $$;

-- Anular a entrada às 07:00 (UPDATE direto como superuser — o trigger de
-- imutabilidade só bloqueia alterações a tipo/empresa_id/verificacao_id;
-- as colunas anulada* são livres).
update picagem
   set anulada          = true,
       anulada_em       = '2026-07-03 07:05:00+00',
       motivo_anulacao  = 'hora de chegada errada — corrigida às 07:15'
 where verificacao_id = 'd0930000-0000-0000-0000-000000000001';

-- TESTE 4 — após anulação, sequencia_valida aceita nova entrada
--           (o lookup de sequencia_valida exclui anuladas — invariante 5)
do $$
begin
  if not public.sequencia_valida(
       '11111111-1111-1111-1111-111111111111',
       'd0900000-0000-0000-0000-000000000001',
       'entrada',
       '2026-07-03 07:10:00+00')
  then
    raise exception
      'FALHA T4: sequencia_valida rejeitou entrada após anulação (anulada não devia contar)';
  end if;
  raise notice 'TESTE 4 (sequencia_valida ignora picagem anulada — entrada volta a ser válida): OK';
end $$;

-- 3b. Correção manual: entrada às 07:15 + saida às 16:00
--
-- Cálculo manual de trabalho (usando momento_dispositivo):
--   entrada 07:15 → saida 16:00 = 8h 45min = 8*3600 + 45*60 = 28800 + 2700 = 31500 s
-- Se a anulada contasse, haveria 2 turnos e o fechado = false (entrada 07:00 sem saida).
insert into verificacao
  (id, empresa_id, trabalhador_id, loja_id,
   momento_dispositivo, momento_servidor, correcao_manual)
values
  ('d0930000-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-03 07:15:00+00', '2026-07-03 07:15:00+00', true),
  ('d0930000-0000-0000-0000-000000000003',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-03 16:00:00+00', '2026-07-03 16:00:00+00', false);

insert into picagem (empresa_id, verificacao_id, tipo) values
  ('11111111-1111-1111-1111-111111111111',
   'd0930000-0000-0000-0000-000000000002', 'entrada'),
  ('11111111-1111-1111-1111-111111111111',
   'd0930000-0000-0000-0000-000000000003', 'saida');

-- TESTE 5 — dia 3: anulada não conta para horas nem para contagem de turnos
--   trabalho esperado = 31500 s (07:15→16:00); turnos = 1; fechado = true
--   Se a anulada contasse: turnos = 2 e todos_fechados = false.
do $$
declare r record;
begin
  select * into r
    from public.vista_horas_dia
   where trabalhador_id = 'd0900000-0000-0000-0000-000000000001'
     and dia = '2026-07-03';

  if r is null then
    raise exception 'FALHA T5: dia 2026-07-03 não aparece em vista_horas_dia';
  end if;
  if r.seg_trabalho <> 31500 then
    raise exception
      'FALHA T5: trabalho esperado 31500 s (07:15→16:00 sem anulada), obtido % s',
      r.seg_trabalho;
  end if;
  if r.turnos <> 1 then
    raise exception
      'FALHA T5: esperado 1 turno (anulada não cria turno), obtido %', r.turnos;
  end if;
  if not r.todos_fechados then
    raise exception
      'FALHA T5: dia 3 devia estar fechado (turno tem saida; anulada sem saida não conta)';
  end if;
  raise notice 'TESTE 5 (dia 3: 31500 s trabalho, 1 turno, anulada excluída): OK';
end $$;

-- =====================================================================
-- Dia 4 (2026-07-04): picagem com desvio dispositivo/servidor
--
-- Entrada: momento_dispositivo = 07:00 UTC
--          momento_servidor    = 07:07:00 UTC  → desvio = 420 s
--          (> limiar de 300 s; constante em packages/core)
-- Saida:   momento_dispositivo = momento_servidor = 16:00 UTC → desvio = 0
-- =====================================================================
insert into verificacao
  (id, empresa_id, trabalhador_id, loja_id, momento_dispositivo, momento_servidor)
values
  -- entrada com desvio de 420 s
  ('d0940000-0000-0000-0000-000000000001',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-04 07:00:00+00',
   '2026-07-04 07:07:00+00'),   -- servidor chegou 420 s depois do dispositivo
  -- saida sem desvio
  ('d0940000-0000-0000-0000-000000000002',
   '11111111-1111-1111-1111-111111111111',
   'd0900000-0000-0000-0000-000000000001',
   'a1100000-0000-0000-0000-000000000001',
   '2026-07-04 16:00:00+00',
   '2026-07-04 16:00:00+00');

insert into picagem (empresa_id, verificacao_id, tipo) values
  ('11111111-1111-1111-1111-111111111111',
   'd0940000-0000-0000-0000-000000000001', 'entrada'),
  ('11111111-1111-1111-1111-111111111111',
   'd0940000-0000-0000-0000-000000000002', 'saida');

-- TESTE 6 — vista_picagem.desvio_segundos = 420 na picagem com desvio injetado
--   desvio_segundos = extract(epoch from momento_servidor - momento_dispositivo)::int
--   = extract(epoch from '07:07:00'+'00' - '07:00:00+00') = 420
do $$
declare v_desvio int;
begin
  select desvio_segundos into v_desvio
    from public.vista_picagem
   where verificacao_id = 'd0940000-0000-0000-0000-000000000001';

  if v_desvio is null then
    raise exception 'FALHA T6: linha não encontrada em vista_picagem para verificacao d0940000...001';
  end if;
  if v_desvio <> 420 then
    raise exception 'FALHA T6: desvio esperado 420 s, obtido % s', v_desvio;
  end if;
  raise notice 'TESTE 6 (desvio_segundos = 420 na entrada com desvio injetado): OK';
end $$;

-- TESTE 7 — vista_picagem.desvio_segundos = 0 nas picagens sem desvio
--   verificacao d0910000...001 = entrada dia 1, momento_dispositivo = momento_servidor
do $$
declare v_desvio int;
begin
  select desvio_segundos into v_desvio
    from public.vista_picagem
   where verificacao_id = 'd0910000-0000-0000-0000-000000000001';

  if v_desvio is null then
    raise exception 'FALHA T7: linha não encontrada em vista_picagem para verificacao d0910000...001';
  end if;
  if v_desvio <> 0 then
    raise exception 'FALHA T7: desvio esperado 0 s, obtido % s', v_desvio;
  end if;
  raise notice 'TESTE 7 (desvio_segundos = 0 em picagem sem desvio): OK';
end $$;

rollback;

select 'DOD FRENTE A: TODOS OS TESTES PASSARAM' as resultado;
