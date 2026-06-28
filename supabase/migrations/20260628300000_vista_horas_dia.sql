-- ============================================================================
-- Cálculo de horas (Frente A) — vista on-the-fly, sempre atual
-- ----------------------------------------------------------------------------
-- Modelo de SEGMENTOS COM ESTADO (não emparelha entrada↔saída):
--   após entrada / fim_intervalo -> 'trabalho'
--   após inicio_intervalo        -> 'pausa'
--   após saida                   -> 'fora'
-- Horas de trabalho = soma dos segmentos 'trabalho' com fim conhecido.
-- Pausas descontam-se sozinhas (Art. 202.º CT). Vários turnos por dia: ok.
--
-- TURNO = entre entradas (running count). Atribuído ao DIA DE LISBOA DA ENTRADA
-- -> um turno que passa da meia-noite conta inteiro no dia em que começou.
--
-- FLAGS:
--   incompleto      = algum turno do dia sem saída (em curso hoje, ou esquecida)
--   todos_fechados  = todos os turnos do dia fecharam com saída
-- Segmentos sem fim (turno aberto) NÃO são contados — não se inventa uma saída.
--
-- security_invoker: a RLS do admin aplica-se -> só vê a sua empresa.
-- Agregação semana/mês: GROUP BY date_trunc('week'|'month', dia) por cima.
-- ============================================================================

begin;

create or replace view public.vista_horas_dia
with (security_invoker = true) as
with eventos as (
  select
    v.empresa_id, v.trabalhador_id,
    v.momento_dispositivo as momento, p.tipo,
    count(*) filter (where p.tipo = 'entrada')
      over (partition by v.empresa_id, v.trabalhador_id
            order by v.momento_dispositivo
            rows between unbounded preceding and current row) as turno_no
  from public.picagem p
  join public.verificacao v
    on v.id = p.verificacao_id and v.empresa_id = p.empresa_id
),
segmentos as (
  select
    empresa_id, trabalhador_id, turno_no, momento, tipo,
    lead(momento) over (partition by empresa_id, trabalhador_id, turno_no
                        order by momento) as fim,
    case
      when tipo in ('entrada','fim_intervalo') then 'trabalho'
      when tipo = 'inicio_intervalo'           then 'pausa'
      else 'fora'
    end as estado
  from eventos
),
turnos as (
  select
    empresa_id, trabalhador_id, turno_no,
    date_trunc('day', (min(momento) at time zone 'Europe/Lisbon'))::date as dia,
    coalesce(sum(case when estado='trabalho' and fim is not null
                      then extract(epoch from (fim - momento)) end), 0) as seg_trab,
    coalesce(sum(case when estado='pausa' and fim is not null
                      then extract(epoch from (fim - momento)) end), 0) as seg_pausa,
    bool_or(tipo = 'saida') as fechado,
    bool_or(estado in ('trabalho','pausa') and fim is null) as tem_aberto
  from segmentos
  group by empresa_id, trabalhador_id, turno_no
)
select
  empresa_id,
  trabalhador_id,
  dia,
  round((sum(seg_trab)  / 3600.0)::numeric, 2) as horas_trabalho,
  round((sum(seg_pausa) / 3600.0)::numeric, 2) as horas_pausa,
  sum(seg_trab)::int   as seg_trabalho,
  sum(seg_pausa)::int  as seg_pausa,
  count(*)             as turnos,
  bool_and(fechado)    as todos_fechados,
  bool_or(not fechado or tem_aberto) as incompleto
from turnos
group by empresa_id, trabalhador_id, dia;

grant select on public.vista_horas_dia to authenticated;

commit;
